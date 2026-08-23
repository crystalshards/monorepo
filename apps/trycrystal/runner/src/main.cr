# Entry point. Two lives in one binary:
#
#   trycrystal-runner                     HTTP execution service
#   trycrystal-runner --sandbox-exec --   per-execution confinement trampoline
#
# The trampoline branch must be checked before anything else, because it runs
# in the forked child of every submission.

require "json"
require "file_utils"
require "./config"
require "./wrap"
require "./sandbox_exec"
require "http/server"
require "./executor"
require "./http_server"

if ARGV.first? == "--sandbox-exec"
  # Drop the flag and the separator; the rest is the command.
  rest = ARGV[1..]
  rest.shift if rest.first == "--"
  TryCrystalRunner::SandboxExec.run(rest)
  exit 1
end

module TryCrystalRunner
  VERSION = "0.1.0"

  def self.boot
    config = Config.load

    if config.confined?
      # Confined mode gets a clean exec: the kernel's per-process environment
      # (what /proc/<pid>/environ reports) is recorded at execve and clearenv
      # cannot change it, so the only way to keep platform variables (canaries
      # included) away from same-uid /proc readers is to become a new exec
      # that never carried them. Marker RUNNER_ENV_SCRUBBED prevents a loop.
      unless ENV["RUNNER_ENV_SCRUBBED"]? == "1"
        keep = {"PORT", "TRYC_SANDBOX", "PATH"}
        clean = {"RUNNER_ENV_SCRUBBED" => "1"}
        ENV.each do |key, _|
          clean[key] = ENV[key] if key.starts_with?("RUNNER_") || keep.includes?(key)
        end
        Process.exec(
          Process.executable_path || PROGRAM_NAME,
          ARGV,
          env: clean,
          clear_env: true
        )
      end

      # Confinement that cannot be proven is confinement we do not have.
      confine_self_checks(config)
    end

    prepare_scratch(config)
    crystal_version = probe_crystal(config)

    if config.confined?
      boot_self_test(config)
    end

    executor = Executor.new(config)
    HTTPServer.new(config, executor, crystal_version).start
  end

  # What the runner can check about its own container before serving: it must
  # not be root, and the scratch root must be writable. The seccomp half of
  # the proof runs on every execution inside the trampoline, and the boot
  # self-test below exercises that whole path once before the port opens.
  private def self.confine_self_checks(config)
    uid = LibC.getuid
    unless uid != 0
      raise ConfinementError.new(
        "refusing to start: confined mode requires a non-root user (running as uid 0); " \
        "set the image's USER to an unprivileged account"
      )
    end

    {% unless flag?(:linux) %}
      raise ConfinementError.new(
        "refusing to start: TRYC_SANDBOX=cloudrun requires Linux (seccomp confinement); " \
        "this build cannot confine. Use ALLOW_UNSAFE=true on developer workstations."
      )
    {% end %}
  end

  private def self.prepare_scratch(config)
    begin
      FileUtils.mkdir_p(config.scratch_root)
      probe = File.join(config.scratch_root, ".write-probe")
      File.write(probe, "ok")
      File.delete(probe)
    rescue ex
      raise ConfinementError.new(
        "refusing to start: scratch root #{config.scratch_root.inspect} is not writable (#{ex.class}); " \
        "mount a writable volume there or set RUNNER_SCRATCH_ROOT"
      )
    end
  end

  # Runs `crystal --version` once at boot. This is also the presence check:
  # a runner whose compiler is missing fails to boot rather than failing on
  # the first submission.
  private def self.probe_crystal(config) : String
    output = IO::Memory.new
    status = Process.run(config.crystal_bin, ["--version"], output: output, error: Process::Redirect::Inherit)
    unless status.success?
      raise ConfinementError.new(
        "refusing to start: #{config.crystal_bin} --version exited #{status.exit_code}; " \
        "the execution compiler is missing or broken (set RUNNER_CRYSTAL_BIN)"
      )
    end
    output.to_s.lines.first?.try(&.strip) || "unknown"
  end

  # One real execution through the full path (trampoline, rlimits, seccomp,
  # capture, wipe) before the port opens. If confinement cannot actually run
  # a program, the runner refuses to serve.
  private def self.boot_self_test(config)
      executor = TryCrystalRunner::Executor.new(config)
      result = executor.execute(%(puts "trycrystal-runner boot self-test"), 30_000)
    unless result.exit_code == 0 && result.stdout.includes?("trycrystal-runner boot self-test")
      raise ConfinementError.new(
        "refusing to start: boot self-test failed (exit #{result.exit_code}, " \
        "stdout #{result.stdout.inspect}, stderr #{result.stderr[0, 500].inspect}). " \
        "Confinement that cannot execute a program is not confinement."
      )
    end
  end
end

begin
  TryCrystalRunner.boot
rescue ex : TryCrystalRunner::ConfinementError
  STDERR.puts "trycrystal-runner: #{ex.message}"
  exit 1
rescue ex : Exception
  STDERR.puts "trycrystal-runner: boot failed: #{ex.class} #{ex.message}\n#{ex.backtrace.try &.first(5).join("\n")}"
  exit 1
end
