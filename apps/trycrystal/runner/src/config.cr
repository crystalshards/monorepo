# Startup configuration and the fail-closed confinement gate.
#
# The runner executes untrusted Crystal on every request. It refuses to serve
# unless it can see confinement, and the only opt-out is the exact string
# ALLOW_UNSAFE=true. A truthy-looking value is not the string and must refuse:
# the point of an opt-out this awkward is that it cannot be typed by accident
# or inherited from some other variable's convention.

module TryCrystalRunner
  CONFINE_MARKER_EXPECTED = "cloudrun"

  class ConfinementError < Exception
  end

  struct Config
    getter? confined : Bool
    getter? unsafe : Bool
    property port : Int32
    property crystal_bin : String
    property exec_mode : String
    property scratch_root : String
    property max_timeout_ms : Int32
    property default_timeout_ms : Int32
    property max_output_bytes : Int32
    property concurrency : Int32
    property limit_as_bytes : UInt64
    property limit_cpu_seconds : Int64
    property limit_nproc : UInt64
    property limit_fsize_bytes : UInt64
    property limit_nofile : UInt64

    def self.load
      confine_marker = ENV["TRYC_SANDBOX"]?
      unsafe_raw = ENV["ALLOW_UNSAFE"]?

      confined = confine_marker == CONFINE_MARKER_EXPECTED
      unsafe = unsafe_raw == "true"

      new(
        confined: confined,
        unsafe: unsafe,
        confine_marker: confine_marker,
        unsafe_raw: unsafe_raw,
        port: int_env("PORT", 9292),
        crystal_bin: ENV["RUNNER_CRYSTAL_BIN"]? || "crystal",
        exec_mode: exec_mode_env,
        scratch_root: ENV["RUNNER_SCRATCH_ROOT"]? || default_scratch_root(confined),
        max_timeout_ms: int_env("RUNNER_MAX_TIMEOUT_MS", 30_000),
        default_timeout_ms: int_env("RUNNER_DEFAULT_TIMEOUT_MS", 20_000),
        max_output_bytes: int_env("RUNNER_MAX_OUTPUT_BYTES", 1_048_576),
        concurrency: int_env("RUNNER_CONCURRENCY", 1),
        # Address space. Linux enforces this hard (RLIMIT_AS covers every
        # mapping, anonymous and file-backed). The floor is what
        # `crystal run` itself needs to compile a stdlib-requiring program,
        # measured in the runtime image, not guessed.
        limit_as_bytes: uint_env("RUNNER_LIMIT_AS", 3_221_225_472),
        # CPU seconds. Must sit ABOVE the wall-clock max: if it is
        # smaller, a long requested timeout is killed by SIGXCPU first
        # and we report timed_out=false for a time kill (measured:
        # timeout_ms=20000, RLIMIT_CPU=15, duration 14967, timed_out
        # false). The wall timer is the contract field; this is the
        # backstop.
        limit_cpu_seconds: int64_env("RUNNER_LIMIT_CPU_S", 60),
        # shared-uid dev machines where it would count unrelated processes.
        limit_nproc: uint_env("RUNNER_LIMIT_NPROC", default_nproc(confined)),
        # Per-file write cap. Object files from a stdlib compile are a few
        # MiB each; 64 MiB leaves compile headroom and stops a submission
        # filling the scratch volume.
        limit_fsize_bytes: uint_env("RUNNER_LIMIT_FSIZE", 67_108_864),
        # Descriptor cap for the submission and its children.
        limit_nofile: uint_env("RUNNER_LIMIT_NOFILE", 256),
      )
    end

    private def self.default_scratch_root(confined)
      confined ? "/scratch" : "/tmp/trycrystal-runner"
    end

    private def self.default_nproc(confined)
      # Per-uid, and Linux counts threads. The server, the trampoline, the
      # compiler's workers and cc/ld all share this uid, so the number has
      # to clear a real `crystal run` (measured: 64 was not enough and
      # pthread_create failed with EAGAIN). 256 still stops a fork bomb.
      confined ? 256_u64 : 0_u64
    end

    private def self.exec_mode_env : String
      raw = ENV["RUNNER_EXEC_MODE"]?
      if raw
        unless raw == "run" || raw == "i"
          raise ConfinementError.new(
            "RUNNER_EXEC_MODE=#{raw.inspect} is not \"run\" or \"i\""
          )
        end
        return raw
      end
      # Unset: the interpreter image ships crystal-i and must default to
      # `i` so a deployer cannot forget the env var. The run-mode image
      # uses a binary named `crystal` and stays on `run`. Explicit
      # RUNNER_EXEC_MODE=run remains the escape hatch on either image.
      bin = ENV["RUNNER_CRYSTAL_BIN"]? || "crystal"
      File.basename(bin) == "crystal-i" ? "i" : "run"
    end

    def initialize(@confined : Bool, @unsafe : Bool, confine_marker : String?, unsafe_raw : String?,
                   @port : Int32, @crystal_bin : String, @exec_mode : String, @scratch_root : String,
                   @max_timeout_ms : Int32, @default_timeout_ms : Int32,
                   @max_output_bytes : Int32, @concurrency : Int32,
                   @limit_as_bytes : UInt64, @limit_cpu_seconds : Int64,
                   @limit_nproc : UInt64, @limit_fsize_bytes : UInt64, @limit_nofile : UInt64)
      if @confined && @unsafe
        raise ConfinementError.new(
          "TRYC_SANDBOX=cloudrun and ALLOW_UNSAFE=true are both set; " \
          "a confined runner must not also opt out of confinement"
        )
      end

      unless @confined || @unsafe
        missing = [] of String
        missing << "TRYC_SANDBOX=#{CONFINE_MARKER_EXPECTED} is not set" unless confine_marker
        missing << "TRYC_SANDBOX is #{confine_marker.inspect}, not \"#{CONFINE_MARKER_EXPECTED}\"" if confine_marker && !@confined
        missing << "ALLOW_UNSAFE is #{unsafe_raw.inspect}, not exactly \"true\"" if unsafe_raw && unsafe_raw != "true"
        missing << "ALLOW_UNSAFE is not set" unless unsafe_raw
        raise ConfinementError.new(
          "refusing to start: confinement is unconfigured. " \
          "Missing: #{missing.join("; ")}. " \
          "The only opt-out is the exact string ALLOW_UNSAFE=true."
        )
      end

      if @unsafe
        STDERR.puts "trycrystal-runner: ALLOW_UNSAFE=true, running unconfined. " \
                    "Never use this where the submissions are not yours."
      end
    end

    private def self.int_env(name, default)
      raw = ENV[name]?
      return default unless raw
      value = raw.to_i?
      raise ConfinementError.new("#{name}=#{raw.inspect} is not an integer") unless value
      value
    end

    private def self.int64_env(name, default)
      raw = ENV[name]?
      return default.to_i64 unless raw
      value = raw.to_i64?
      raise ConfinementError.new("#{name}=#{raw.inspect} is not an integer") unless value
      value
    end

    private def self.uint_env(name, default : UInt64) : UInt64
      raw = ENV[name]?
      return default unless raw
      value = raw.to_u64?
      raise ConfinementError.new("#{name}=#{raw.inspect} is not an unsigned integer") unless value
      value
    end
  end
end
