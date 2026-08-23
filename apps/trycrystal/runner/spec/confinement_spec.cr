# Confinement proof for the trycrystal runner.
#
# DESIGN.md section 5, obligations 1-3:
#
#   1. A hostile fixture, executed through the real runner path, writes probe
#      results showing every escape route blocked AND real output still
#      produced, so the suite cannot pass merely because execution broke.
#   2. Missing probe lines fail loudly. A helper that returned an empty string
#      for an absent probe would make every "should_not contain" assertion
#      pass vacuously when execution never happened.
#   3. The same fixture runs UNCONFINED as a negative control and must LEAK.
#      A containment test that cannot fail proves nothing.
#
# There are two proof layers, and the split is deliberate:
#
#   mechanism   The confinement primitives themselves, proven on the
#               docs-build substrate (apps/docs-build: no-egress seccomp
#               filter, uid drop, environment scrub) with `crystal run`,
#               inside docker on a Linux kernel. This is the Cloud Run shape:
#               the container has a working network (Cloud Run containers
#               always do), and egress is denied INSIDE the process by a
#               seccomp filter that survives execve. Runnable today; does not
#               depend on the runner service existing.
#
#   service     The real runner path: the runner image started with
#               TRYC_SANDBOX=cloudrun, hostile submission POSTed to
#               /execute, probe lines parsed out of the JSON response. The
#               negative control runs the same image with ALLOW_UNSAFE=true
#               and must leak. Activates as soon as the runner image builds.
#
# Run from apps/trycrystal/runner: crystal spec spec/confinement_spec.cr
#
# Requires docker. Skips with a stated reason, never silently passes, when
# docker or an image is unavailable: a skipped proof is a missing proof, and
# reading one as a pass is exactly the vacuous-pass failure mode this spec
# exists to prevent.

require "spec"
require "http/client"
require "json"

FIXTURE_PATH = File.expand_path("fixtures/hostile_submission.cr", __DIR__)

# The substrate that carries the confinement primitives under proof. Built
# from apps/docs-build, which ships no-egress (the seccomp egress filter the
# runner's trampoline ports) and egress-probe. The tag is private to this
# spec so it cannot collide with the docs containment spec's own image.
SUBSTRATE_IMAGE = "trycrystal-proof:substrate"
SUBSTRATE_CONTEXT = File.expand_path("../../../docs-build", __DIR__)

# The runner's own image and service, owned by the Runner slice.
RUNNER_IMAGE = "trycrystal-runner:proof"
RUNNER_PORT = 9292

# What an operator must never be able to read out of the execution
# environment. Set on the CONTAINER (the server's environment), never handed
# to the submission; every probe that finds it is a leak.
CANARY_VALUE = "canary-must-not-escape"

def docker_available? : Bool
  Process.run("docker", ["info"], output: Process::Redirect::Close, error: Process::Redirect::Close).success?
rescue
  false
end

def build_image!(tag : String, context : String, dockerfile : String? = nil) : Bool
  args = ["build", "-q", "-t", tag]
  args += ["-f", dockerfile] if dockerfile
  args << context
  Process.run("docker", args, output: Process::Redirect::Close, error: Process::Redirect::Close).success?
end

# ---------------------------------------------------------------- probes ----

# Raised when an expected PROBE line is absent from an execution's output.
#
# This is the load-bearing failure: the naive alternative is a helper that
# returns "" for a missing probe, under which `should_not contain("LEAKED")`
# passes for every probe of an execution that never ran. Absence is an error
# here, and the message carries the whole output so the failure explains
# itself.
class MissingProbe < Exception; end

# Extracts the `PROBE <name>: <result>` line's result from an execution's
# combined output. Absent line raises MissingProbe; it never returns an
# empty string for a probe that was never produced.
def probe_result(output : String, name : String) : String
  prefix = "PROBE #{name}:"
  line = output.lines.find { |candidate| candidate.starts_with?(prefix) }
  raise MissingProbe.new(
    "expected a #{prefix} line and there was none, so the execution never " \
    "produced this probe; every assertion about it would be vacuous. " \
    "Combined output was:\n#{output}"
  ) unless line
  line.not_nil![prefix.size..].strip
end

# Runs the fixture inside the substrate image, one of two ways:
#
#   confined: the Cloud Run shape. The wrapper shell (pid 1, root, holding
#     TRYC_CANARY) hands execution to `no-egress --user 1000:1000` through
#     `env -i`, so the compile and run happen with a scrubbed environment, at
#     uid 1000, under the seccomp no-egress filter. The container's own
#     network is UP the whole time: egress is denied in-process, which is the
#     only form of egress denial Cloud Run offers.
#
#   unconfined: the negative control. Same image, same fixture, same machine,
#     same network. No filter, no uid drop, no scrub: the shell runs the
#     compile directly as root with the container's environment inherited.
#
# Everything that differs between the two legs is confinement and nothing
# else, which is what makes "blocked" in one and "LEAKED" in the other a
# measurement rather than a coincidence.
def run_mechanism_leg(confined : Bool) : NamedTuple(status: Int32, output: String)
  output = IO::Memory.new

  common = [
    "run", "--rm",
    "-e", "TRYC_CANARY=#{CANARY_VALUE}",
    "-v", "#{FIXTURE_PATH}:/probe/fixture.cr:ro",
    "--entrypoint", "/bin/sh",
    SUBSTRATE_IMAGE,
  ]

  # Both legs wrap the execution in a supervising shell that STAYS pid 1 for
  # the whole run. This is not cosmetic. busybox ash tail-execs a -c body
  # that is a single AND-list, so `sh -c 'prep && exec-me'` turns exec-me
  # into pid 1 itself: /proc/1/environ then belongs to the confined process,
  # and the uid-split boundary is never exercised. Ending the body with a
  # `; status=$?; sleep 0.2; exit $status` tail keeps the supervisor alive
  # as pid 1, which is the docs-build shape: a privileged supervisor holding
  # secrets, and the untrusted execution below it.
  command = if confined
              # --network is deliberately NOT "none": the production platform
              # cannot remove the network, so the proof must not either. The
              # boundary under test is the in-process filter.
              #
              # The supervisor (pid 1, root, holding TRYC_CANARY) hands
              # execution to no-egress through env -i, so the compile and
              # run happen with a scrubbed environment, at uid 1000, under
              # the seccomp filter.
              "mkdir -p /scratch/home /scratch/cache /scratch/tmp; chmod -R 777 /scratch; " \
                "env -i PATH=/usr/local/bin:/usr/bin:/bin HOME=/scratch/home TMPDIR=/scratch/tmp " \
                "CRYSTAL_CACHE_DIR=/scratch/cache " \
                "no-egress --user 1000:1000 crystal run /probe/fixture.cr; " \
                "status=\$?; sleep 0.2; exit \$status"
            else
              # Identical supervision, no confinement: same pid 1 holding the
              # same canary, same fixture, same machine, same network. The
              # child differs in privilege only.
              "crystal run /probe/fixture.cr; status=\$?; sleep 0.2; exit \$status"
            end

  status = Process.run("docker", common + ["-c", command], output: output, error: output)
  {status: status.exit_code, output: output.to_s}
end
# ------------------------------------------------------ mechanism layer ----

describe "confinement mechanism on the docs-build substrate" do
  it "leaks every secret it can reach when unconfined (negative control)" do
    pending! "docker is not available" unless docker_available?
    pending! "could not build #{SUBSTRATE_IMAGE}" unless build_image!(SUBSTRATE_IMAGE, SUBSTRATE_CONTEXT)

    leg = run_mechanism_leg(confined: false)
    output = leg[:output]

    # Real work happened, so the leak assertions below cannot be satisfied by
    # a broken execution. crystal run's exit is the submission's exit.
    output.should contain("LESSON_OK sum=20")

    # The canary, read out of the inherited environment, at macro time
    # (inside the compiling process) and at run time.
    probe_result(output, "macro-env").should eq("LEAKED")
    probe_result(output, "runtime-env").should eq("LEAKED")

    # Outbound network, both boundaries.
    probe_result(output, "macro-net").should eq("REACHABLE")
    probe_result(output, "runtime-net").should eq("REACHABLE")
    probe_result(output, "runtime-dns").should eq("RESOLVED")

    # The supervisor's environment is readable at the same uid, and it holds
    # the canary: this is the full leak the confined leg must not reproduce.
    probe_result(output, "runtime-proc1env").should eq("READABLE+CANARY-FOUND")

    # Root: the whole container filesystem is writable.
    probe_result(output, "runtime-uid").should contain("uid=0")
    probe_result(output, "runtime-rootfs").should eq("WRITABLE-root")
    probe_result(output, "runtime-rootfs-etc").should eq("WRITABLE-etc")
  end

  it "blocks every route and still produces real output when confined" do
    pending! "docker is not available" unless docker_available?
    pending! "could not build #{SUBSTRATE_IMAGE}" unless build_image!(SUBSTRATE_IMAGE, SUBSTRATE_CONTEXT)

    leg = run_mechanism_leg(confined: true)
    output = leg[:output]

    # The submission still did its real work. Without this, "everything
    # blocked" could mean "execution broke".
    output.should contain("LESSON_OK sum=20")

    # The canary is gone at both boundaries: the environment was scrubbed
    # before exec, and what scrubbing misses the uid split covers.
    probe_result(output, "macro-env").should eq("scrubbed")
    probe_result(output, "runtime-env").should eq("scrubbed")

    # No egress at either boundary, and the refusal is the filter's own
    # errno: "address family not supported" is what socket(2) returns when
    # the seccomp filter denies the family. Any other error would mean the
    # socket was created and something else failed.
    probe_result(output, "macro-net").should start_with("REFUSED")
    probe_result(output, "runtime-net").downcase.should contain("address family")
    probe_result(output, "runtime-metadata").downcase.should contain("address family")
    probe_result(output, "runtime-dns").should start_with("REFUSED")

    # The supervisor (pid 1, root, holding the canary) is off limits at
    # uid 1000: environment and memory both refused.
    probe_result(output, "runtime-proc1env").should eq("REFUSED")
    probe_result(output, "runtime-proc1mem").should eq("REFUSED")

    # Not root, and the system filesystem is not writable by the submission.
    probe_result(output, "runtime-uid").should_not contain("uid=0")
    probe_result(output, "runtime-uid").should contain("uid=1000")
    probe_result(output, "runtime-rootfs").should eq("root-refused")
    probe_result(output, "runtime-rootfs-etc").should eq("etc-refused")

    # The kernel's own account: no capabilities, no route back to privilege,
    # and a seccomp filter installed in the execution process itself.
    caps = probe_result(output, "runtime-caps")
    caps.should match(/CapEff:\s+0{8,16}/)
    caps.should match(/NoNewPrivs:\s+1/)
    caps.should match(/Seccomp:\s+2/)
  end

  it "fails loudly when a probe line is missing rather than reading as empty" do
    # The demonstration required by DESIGN.md section 5.2: absence is an
    # error. A helper that returned "" here would let the next two
    # assertions pass on output that never contained the probe at all:
    #
    #   probe_result(broken, "net").should_not contain("LEAKED")  # vacuous
    #   probe_result(broken, "net").should eq("")                 # "passes"
    #
    # An execution that produced no PROBE line for a name is a broken
    # execution, and this spec treats it as one.
    broken = "LESSON_OK sum=20\nPROBE runtime-env: scrubbed\n"

    expect_raises(MissingProbe, /never produced this probe/) do
      probe_result(broken, "runtime-net")
    end
  end
end

# -------------------------------------------------------- service layer ----

# Starts the real runner image and returns a handle for POSTing submissions.
# `unsafe: true` boots it with ALLOW_UNSAFE=true, the exact-string opt-out;
# anything else boots confined with TRYC_SANDBOX=cloudrun.
class RunnerContainer
  getter port : Int32
  @name : String
  @image : String

  # Built once per process: both examples use the same image, and a rebuild
  # of an unchanged context is pure waiting.
  @@image_built : Bool? = nil

  def initialize(@unsafe : Bool)
    @name = "trycrystal-proof-#{Random::Secure.hex(6)}"
    @port = 0

    # A pre-built image wins over building one. CI builds the runner image
    # in its own step, and a proof that insists on rebuilding it here would
    # be proving a different image from the one that ships.
    if image = ENV["TRYC_RUNNER_IMAGE"]?
      @image = image
    else
      @image = RUNNER_IMAGE
      dockerfile = File.expand_path("../Dockerfile", __DIR__)
      @@image_built ||= Process.run(
        "docker",
        ["build", "-q", "-t", RUNNER_IMAGE, "-f", dockerfile,
         File.expand_path("..", __DIR__)],
        output: Process::Redirect::Close, error: Process::Redirect::Close
      ).success?
      raise "could not build #{RUNNER_IMAGE}" unless @@image_built
    end

    output = IO::Memory.new
    args = [
      # Deliberately NOT --rm: a container that refuses to start is the most
      # informative thing in this spec, and --rm reaps it before its logs and
      # exit code can be read. `close` removes it explicitly instead.
      "run", "-d", "--name", @name,
      "-p", "127.0.0.1::9292",
      # Scratch as a tmpfs, with exec. Docker's --tmpfs defaults to noexec,
      # and `crystal run` execs the binary it just linked, so a noexec
      # scratch breaks every submission for a reason that has nothing to do
      # with confinement.
      #
      # Deliberately no --read-only: Cloud Run's container filesystem IS
      # writable (in-memory, per instance), and the control that keeps a
      # submission out of the system paths is the non-root uid. Passing
      # --read-only here would prove a stricter world than the one that
      # ships, and the rootfs probes would pass for the wrong reason.
      "--tmpfs", "/scratch:rw,exec,mode=0700,uid=10001,size=512m",
      # The canary rides in the server's environment. Confined mode scrubs
      # it before any submission runs (the runner boots by re-execing itself
      # with a scrubbed environment, so /proc/1/environ never holds it);
      # unsafe mode skips that scrub, and with server and submission at the
      # same uid the submission can read it straight out of pid 1.
      "-e", "TRYC_CANARY=#{CANARY_VALUE}",
    ]

    # Exactly one mode, never both: the runner refuses to boot when a
    # confined runner is also handed the opt-out, which is correct and is
    # why this is an either/or rather than an added flag.
    args += if @unsafe
              ["-e", "ALLOW_UNSAFE=true"]
            else
              ["-e", "TRYC_SANDBOX=cloudrun"]
            end
    args << @image

    started = Process.run("docker", args, output: output, error: output)
    raise "could not start runner container: #{output.to_s}" unless started.success?

    begin
      @port = wait_for_health
    rescue ex
      # The constructor raised, so no caller holds this object and nobody
      # will call close. Read the corpse's story into the error, then remove
      # it: a leaked container would collide with the next run by name.
      close
      raise ex
    end
  end

  # POSTs the hostile fixture through the real path and returns the parsed
  # response plus the combined text the probe parser works over.
  def execute(code : String) : JSON::Any
    response = HTTP::Client.post(
      "http://127.0.0.1:#{@port}/execute",
      headers: HTTP::Headers{"Content-Type" => "application/json"},
      body: {"code" => code, "timeout_ms" => 10_000}.to_json
    )
    response.status_code.should eq(200), "runner returned #{response.status_code}: #{response.body}"
    JSON.parse(response.body)
  end

  def close
    Process.run("docker", ["rm", "-f", @name],
      output: Process::Redirect::Close, error: Process::Redirect::Close)
  end

  # Waits for the container to serve /health, and when it never does, says
  # WHY in the container's own words.
  #
  # The runner's fail-closed gate exits rather than serving when confinement
  # cannot be established, and the confined boot self-test compiles a real
  # submission before binding the port, so "not healthy yet" and "refused to
  # start" look identical from the outside. A harness that reported only a
  # timeout would turn a confinement defect into a vague flake, so a dead
  # container's logs and exit status are part of the failure message.
  private def wait_for_health : Int32
    port_line = IO::Memory.new

    60.times do
      status = Process.run("docker", ["port", @name, "9292"], output: port_line)
      if status.success? && (match = /:(\d+)\s*$/.match(port_line.to_s.strip))
        port = match[1].to_i
        begin
          health = HTTP::Client.get("http://127.0.0.1:#{port}/health")
          return port if health.status_code == 200
        rescue
          # Not listening yet, or gone. The liveness check below decides.
        end
      end
      port_line.clear

      raise "runner container exited before serving /health.\n#{describe_exit}" unless running?
      sleep 0.5.seconds
    end

    raise "runner container never served /health within 30 seconds.\n#{describe_exit}"
  end

  private def running? : Bool
    state = IO::Memory.new
    status = Process.run("docker",
      ["inspect", "-f", "{{.State.Running}}", @name],
      output: state, error: Process::Redirect::Close)
    status.success? && state.to_s.strip == "true"
  end

  # The container's own account of itself: exit code plus whatever it said on
  # the way out. `docker logs` on a --rm container that has already been
  # reaped returns nothing, which is itself worth printing rather than
  # swallowing.
  private def describe_exit : String
    code = IO::Memory.new
    Process.run("docker", ["inspect", "-f", "{{.State.ExitCode}}", @name],
      output: code, error: Process::Redirect::Close)

    logs = IO::Memory.new
    Process.run("docker", ["logs", @name], output: logs, error: logs)

    exit_code = code.to_s.strip
    said = logs.to_s.strip
    [
      exit_code.empty? ? "container is gone (already reaped)" : "exit code #{exit_code}",
      said.empty? ? "it printed nothing" : "it said:\n#{said}",
    ].join("; ")
  end
end

# Whether the service layer can run at all: either an image was handed to us
# (TRYC_RUNNER_IMAGE, which is how CI should drive this) or the runner's own
# Dockerfile exists and builds here.
def runner_image_available? : Bool
  if image = ENV["TRYC_RUNNER_IMAGE"]?
    return Process.run("docker", ["image", "inspect", image],
      output: Process::Redirect::Close, error: Process::Redirect::Close).success?
  end

  dockerfile = File.expand_path("../Dockerfile", __DIR__)
  return false unless File.exists?(dockerfile)
  build_image!(RUNNER_IMAGE, File.expand_path("..", __DIR__),
    dockerfile: dockerfile)
end

describe "runner service confinement through the real HTTP path" do
  it "blocks the hostile submission and still returns its value when confined" do
    pending! "docker is not available" unless docker_available?
    pending! "no runner image: set TRYC_RUNNER_IMAGE or add apps/trycrystal/runner/Dockerfile" unless runner_image_available?

    fixture = File.read(FIXTURE_PATH)
    runner = RunnerContainer.new(unsafe: false)

    begin
      body = runner.execute(fixture)
      combined = "#{body["stdout"].as_s}\n#{body["stderr"].as_s}"

      # The real path still did the real work: lesson output on stdout and
      # the inspected final expression captured as the value. Compile errors
      # and crashes are NOT allowed to masquerade as containment.
      body["exit_code"].as_i.should eq(0), "submission did not run cleanly:\n#{combined}"
      combined.should contain("LESSON_OK sum=20")
      body["value"].as_s.should eq("\"confinement-proof-complete\"")

      # No canary, at either boundary. The runner boots with a scrubbed
      # environment, so even /proc/1/environ must not carry it.
      probe_result(combined, "macro-env").should eq("scrubbed")
      probe_result(combined, "runtime-env").should eq("scrubbed")
      probe_result(combined, "runtime-proc1env").should_not contain("CANARY-FOUND")

      # No egress at either boundary, filter's errno, not a stray failure.
      probe_result(combined, "macro-net").should start_with("REFUSED")
      probe_result(combined, "runtime-net").downcase.should contain("address family")
      probe_result(combined, "runtime-metadata").downcase.should contain("address family")
      probe_result(combined, "runtime-dns").should start_with("REFUSED")

      # Not root. (The runner image runs everything at uid 1000 by design;
      # uid 0 here would mean the image lost its USER line.)
      probe_result(combined, "runtime-uid").should_not contain("uid=0")

      # The system filesystem is not writable by the submission.
      probe_result(combined, "runtime-rootfs").should eq("root-refused")
      probe_result(combined, "runtime-rootfs-etc").should eq("etc-refused")

      # The filter is installed in the execution process itself, with no
      # capabilities and no route back to privilege.
      caps = probe_result(combined, "runtime-caps")
      caps.should match(/CapEff:\s+0{8,16}/)
      caps.should match(/NoNewPrivs:\s+1/)
      caps.should match(/Seccomp:\s+2/)

      # Known residual, recorded in sandbox/VERIFICATION.md rather than
      # hidden: the server and the submission share uid 1000, so
      # /proc/1/mem may OPEN for same-uid access; reading it must still
      # fail. READABLE here would be a real finding.
      probe_result(combined, "runtime-proc1mem").should_not eq("READABLE")
    ensure
      runner.close
    end
  end

  it "leaks through the same HTTP path with ALLOW_UNSAFE=true (negative control)" do
    pending! "docker is not available" unless docker_available?
    pending! "no runner image: set TRYC_RUNNER_IMAGE or add apps/trycrystal/runner/Dockerfile" unless runner_image_available?

    fixture = File.read(FIXTURE_PATH)
    runner = RunnerContainer.new(unsafe: true)

    begin
      body = runner.execute(fixture)
      combined = "#{body["stdout"].as_s}\n#{body["stderr"].as_s}"

      body["exit_code"].as_i.should eq(0), "submission did not run cleanly:\n#{combined}"
      combined.should contain("LESSON_OK sum=20")

      # Unsafe mode skips the boot scrub, so the canary the operator set is
      # sitting in the server's environment, and there is no barrier between
      # the server and the submission: same uid, /proc readable.
      probe_result(combined, "macro-net").should eq("REACHABLE")
      probe_result(combined, "runtime-net").should eq("REACHABLE")
      probe_result(combined, "runtime-dns").should eq("RESOLVED")
      probe_result(combined, "runtime-proc1env").should contain("READABLE")
      probe_result(combined, "runtime-proc1env").should contain("CANARY-FOUND")

      # If any of these fail with the opt-out in force, the negative control
      # is unavailable on this machine and every "blocked" assertion in the
      # confined example above is vacuous rather than proven.
    ensure
      runner.close
    end
  end
end
