# Executes one submission end to end: fresh scratch, wrapped source, the
# trampoline, stream capture with caps, wall-clock timeout with process-group
# kill, value recovery, scratch wipe.

module TryCrystalRunner
  class Executor
    class Result
      property stdout : String = ""
      property stderr : String = ""
      property value : String? = nil
      property exit_code : Int32 = 0
      property? timed_out : Bool = false
      property duration_ms : Int64 = 0

      def to_json(json : JSON::Builder)
        json.object do
          json.field "stdout", @stdout
          json.field "stderr", @stderr
          json.field "value", @value
          json.field "exit_code", @exit_code
          json.field "timed_out", @timed_out
          json.field "duration_ms", @duration_ms
        end
      end
    end

    # One supervised process run. Kept separate from Result because a wrapped
    # run that dies with a wrap-shaped error is retried unwrapped before
    # anything is reported.
    private class Run
      property stdout : String = ""
      property stderr : String = ""
      property exit_code : Int32 = 0
      property? timed_out : Bool = false
      property duration_ms : Int64 = 0
    end

    @gate : Channel(Nil)
    @serial : Int32 = 0

    def initialize(@config : Config)
      capacity = @config.concurrency
      @gate = Channel(Nil).new(capacity)
      capacity.times { @gate.send(nil) }
    end

    # The full contract path: one submission in, one Result out. Caller owns
    # nothing; the scratch directory lives and dies inside.
    def execute(code : String, timeout_ms : Int32) : Result
      timeout_ms = timeout_ms.clamp(1, @config.max_timeout_ms)

      @gate.receive
      scratch = new_scratch_dir
      begin
        plan = TryCrystalRunner.wrap(code)
        user_lines = code.lines.size

        run = run_once(scratch, plan.source, plan.wrapped?, plan.start_line, user_lines, timeout_ms)

        if plan.wrapped? && run.stderr =~ WRAP_SHAPED_ERROR
          # exact bytes unwrapped: a failure class the wrap itself causes
          # disappears, and a user's own error of the same class reproduces
          # itself identically.
          run = run_once(scratch, code, false, 0, 0, timeout_ms)
        else
          run_value = read_value(scratch)
        end

        result = Result.new
        result.stdout = run.stdout
        result.stderr = run.stderr
        result.value = run_value if plan.wrapped?
        result.exit_code = run.exit_code
        result.timed_out = run.timed_out?
        result.duration_ms = run.duration_ms
        result
      ensure
        FileUtils.rm_rf(scratch)
        @gate.send(nil)
      end
    end

    private def run_once(scratch : String, source : String, wrapped : Bool,
                         start_line : Int32, user_lines : Int32, timeout_ms : Int32) : Run
      File.write(File.join(scratch, "submission.cr"), source)
      # mkdir_p rather than mkdir: the unwrapped retry reuses this scratch
      # directory, and a second run must not fail on its own leftovers.
      FileUtils.mkdir_p(File.join(scratch, "home"))
      FileUtils.mkdir_p(File.join(scratch, "tmp"))
      FileUtils.mkdir_p(File.join(scratch, ".cache"))
      # A value file from the wrapped attempt must never be read as if it
      # belonged to the retry.
      value_path = File.join(scratch, ".value")
      File.delete(value_path) if File.exists?(value_path)

      started = Time.monotonic
      seed_compiler_cache(scratch)

      process = Process.new(
        Process.executable_path || PROGRAM_NAME,
        ["--sandbox-exec", "--", @config.crystal_bin, @config.exec_mode, "--no-color", "submission.cr"],
        env: child_env(scratch, wrapped),
        clear_env: true,
        input: Process::Redirect::Close,
        output: Process::Redirect::Pipe,
        error: Process::Redirect::Pipe
      )

      run = supervise(process, timeout_ms)
      run.duration_ms = ((Time.monotonic - started).total_milliseconds).to_i64

      # no-egress prints a one-line proof on stderr before exec. That is
      # for operators, not for the learner's console.
      run.stderr = run.stderr.sub(/^no-egress: verified in-process[^\n]*\n/, "")
      run.stderr = rewrite_lines(run.stderr, start_line, user_lines) if wrapped
      run
    end

    # Captures both streams with caps, runs the wall clock, kills the process
    # group on expiry or cap breach, reaps, then drains leftovers with a
    # bounded grace so grandchildren holding the pipes cannot hang the reply.
    private def supervise(process : Process, timeout_ms : Int32) : Run
      run = Run.new
      cap = @config.max_output_bytes

      stdout = IO::Memory.new
      stderr = IO::Memory.new
      out_done = Channel(Bool).new(1)
      err_done = Channel(Bool).new(1)
      exited = Channel(Process::Status).new(1)
      timer = Channel(Nil).new(1)

      out_io = process.output.not_nil!
      err_io = process.error.not_nil!

      spawn(name: "tc-stdout") do
        capped = false
        begin
          capped = drain(out_io, stdout, cap)
        rescue IO::Error
        end
        out_done.send(capped)
      end

      spawn(name: "tc-stderr") do
        capped = false
        begin
          capped = drain(err_io, stderr, cap)
        rescue IO::Error
        end
        err_done.send(capped)
      end

      spawn(name: "tc-wait") { exited.send(process.wait) }
      spawn(name: "tc-timer") do
        sleep(timeout_ms.milliseconds)
        timer.send(nil)
      end

      timed_out = false
      capped = false
      killed = false
      out_finished = false
      err_finished = false
      status : Process::Status? = nil

      until status
        select
        when s = exited.receive
          status = s
        when flag = out_done.receive
          out_finished = true
          # stdout EOF early or cap hit. A cap hit must stop the run now;
          # a plain EOF just means one stream finished.
          if flag
            capped = true
            unless killed
              killed = true
              kill_group(process)
            end
          end
        when flag = err_done.receive
          err_finished = true
          if flag
            capped = true
            unless killed
              killed = true
              kill_group(process)
            end
          end
        when timer.receive
          timed_out = true
          unless killed
            killed = true
            kill_group(process)
          end
          # Fall through: the next loop iteration reaps via exited.
        end
      end

      # Drain the remainder with a grace deadline. A grandchild holding a
      # pipe write end would otherwise block the reply until it exits.
      # Channels already consumed above are done; waiting on them again
      # would hang until the deadline, which is exactly 2 wasted seconds
      # on every ordinary run.
      grace_deadline = Time.monotonic + 2.seconds
      wait_for_drain(out_done, grace_deadline) unless out_finished
      wait_for_drain(err_done, grace_deadline) unless err_finished

      begin
        out_io.close
      rescue IO::Error
      end
      begin
        err_io.close
      rescue IO::Error
      end
      # Anything still holding the pipes after the grace period dies here.
      kill_group(process) if killed || timed_out || capped

      run.stdout = stdout.to_s.scrub
      run.stderr = stderr.to_s.scrub
      run.timed_out = timed_out
      run.exit_code = exit_code_of(status.not_nil!)
      run.stderr = append_note(run.stderr, "output limit of #{cap} bytes reached; process killed") if capped

      run
    end

    # Reads to EOF, keeping at most `cap` bytes. Returns true when the cap
    # was reached (caller kills the run).
    private def drain(io : IO::FileDescriptor, sink : IO::Memory, cap : Int32) : Bool
      buffer = Bytes.new(65_536)
      kept = 0
      loop do
        read = io.read(buffer)
        break if read == 0
        room = cap - kept
        sink.write(buffer[0, Math.min(read, room)]) if room > 0
        kept += read
        return true if kept >= cap
      end
      false
    end

    # Blocks until the channel yields or the deadline passes.
    private def wait_for_drain(ch : Channel(Bool), deadline : Time::Span)
      return if Time.monotonic >= deadline

      remaining = deadline - Time.monotonic
      fire = Channel(Nil).new(1)
      spawn(name: "tc-grace") do
        sleep(remaining)
        fire.send(nil)
      end

      select
      when ch.receive
      when fire.receive
      end
    end

    # The trampoline is a session leader (setsid before exec), so its pid is
    # the process-group id. Killing the negative pid takes out the compiler,
    # the user binary, and anything either of them spawned, unless a
    # descendant called setsid itself; that escape is bounded by the CPU
    # rlimit and instance recycling and is listed as a residual in the README.
    private def kill_group(process : Process)
      pid = process.pid
      ret = LibC.kill(-pid, LibC::SIGKILL)
      # ESRCH: group already gone; make sure the direct child is dead too.
      if ret == -1
        begin
          process.signal(Signal::KILL)
        rescue ex : SystemError | IO::Error
        end
      end
    end

    private def exit_code_of(status : Process::Status) : Int32
      if status.normal_exit?
        status.exit_code
      elsif signal = status.exit_signal?
        128 + signal.value
      else
        1
      end
    end
    # Copies the image's read-only compiler cache into this execution's
    # writable scratch cache, under the directory name crystal will look
    # up for submission.cr. The seed itself is never written. A missing
    # seed (local macOS dev) is a no-op.
    private def seed_compiler_cache(scratch : String)
      seed = ENV["RUNNER_CACHE_SEED"]?
      return unless seed && File.directory?(seed)

      inner = Dir.children(seed).compact_map do |name|
        path = File.join(seed, name)
        File.directory?(path) ? path : nil
      end.first?
      return unless inner

      # Crystal names the per-program cache dir by the source path with
      # leading slash stripped and remaining slashes turned into dashes.
      # Verified: /tmp/foo/bar/submission.cr -> tmp-foo-bar-submission.cr
      dest_name = File.join(scratch, "submission.cr").sub(/^\//, "").gsub('/', '-')
      dest = File.join(scratch, ".cache", dest_name)
      return if File.exists?(dest)
      FileUtils.cp_r(inner, dest)
      # The seed is installed a-w so tenants cannot poison it. The copy
      # must be writable: crystal writes this program's own objects next
      # to the seeded stdlib ones.
      make_tree_writable(dest)
    end

    private def make_tree_writable(path : String)
      if File.directory?(path)
        File.chmod(path, 0o755)
        Dir.each_child(path) { |name| make_tree_writable(File.join(path, name)) }
      else
        File.chmod(path, 0o644)
      end
    end

    # inherited, because the compiler must be findable.
    private def child_env(scratch : String, wrapped : Bool) : Hash(String, String)
      env = {
        "PATH"              => ENV["PATH"]? || "/usr/local/bin:/usr/bin:/bin",
        "HOME"              => File.join(scratch, "home"),
        "TMPDIR"            => File.join(scratch, "tmp"),
        "TERM"              => "dumb",
        "CRYSTAL_WORKERS"   => "2",
        "CRYSTAL_CACHE_DIR" => File.join(scratch, ".cache"),
        "TC_EXEC_CWD"       => scratch,
        "TC_LIMIT_AS"       => @config.limit_as_bytes.to_s,
        "TC_LIMIT_CPU"      => @config.limit_cpu_seconds.to_s,
        "TC_LIMIT_NPROC"    => @config.limit_nproc.to_s,
        "TC_LIMIT_FSIZE"    => @config.limit_fsize_bytes.to_s,
        "TC_LIMIT_NOFILE"   => @config.limit_nofile.to_s,
        "TC_CONFINED"       => @config.confined? ? "1" : "0",
        "TC_NO_EGRESS"      => ENV["RUNNER_NO_EGRESS"]? || "/usr/local/bin/no-egress",
      }
      if path = ENV["CRYSTAL_PATH"]?
        env = env.merge({"CRYSTAL_PATH" => path})
      end
      env = env.merge({"TC_VALUE_PATH" => File.join(scratch, ".value")}) if wrapped
      env
    end

    private def read_value(scratch : String) : String?
      path = File.join(scratch, ".value")
      File.exists?(path) ? File.read(path).scrub : nil
    end

    # Maps compiler line numbers back to the user's numbering. The wrap
    # inserts one line ("__tc_v = begin") before the final statement and
    # appends machinery after it:
    #   wrapped lines 1..start_line-1           -> unchanged
    #   wrapped lines start_line..user_lines+1  -> minus one
    #   wrapped lines beyond user_lines+1       -> clamped to the last line
    # Excerpt lines in Crystal diagnostics ("  3 | code") follow the same map.
    private def rewrite_lines(stderr : String, start_line : Int32, user_lines : Int32) : String
      return stderr if start_line == 0

      map = ->(n : Int32) do
        if n < start_line
          n
        elsif n <= user_lines + 1
          n - 1
        else
          user_lines
        end
      end

      stderr.gsub(/submission\.cr:(\d+)/) do
        "submission.cr:#{map.call($1.to_i)}"
      end.gsub(/^(\s*)(\d+)( \| )/m) do
        "#{$1}#{map.call($2.to_i)}#{$3}"
      end
    end

    private def append_note(stderr : String, note : String) : String
      marker = "[trycrystal-runner] #{note}"
      stderr.empty? ? marker : "#{stderr}\n#{marker}"
    end

    private def new_scratch_dir : String
      root = @config.scratch_root
      FileUtils.mkdir_p(root)
      loop do
        candidate = File.join(root, "run-#{System.hostname.hash.abs}-#{@serial += 1}-#{rand(999_999)}")
        begin
          Dir.mkdir(candidate, 0o700)
          return candidate
        rescue File::AlreadyExistsError
        end
      end
    end
  end
end
