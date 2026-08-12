module CrystalShards
  # Confines the compile to a container with no network and no inherited
  # environment. Used for local development and CI, and it is the strongest of
  # the two: `--network none` removes the network namespace entirely rather
  # than filtering it.
  class DockerDocsSandbox < DocsSandbox
    def description : String
      "docker, no network, no inherited environment, image #{DocsSandbox.image}"
    end

    def build_docs(source_dir : String, output_dir : String) : Bool
      Dir.mkdir_p(output_dir)

      # The build scratch area is a host directory we own rather than a tmpfs.
      # Crystal's `macro run` compiles a helper binary and executes it during
      # the docs build (ameba does this), and executing a freshly written file
      # from a tmpfs fails under some emulated runtimes. A directory we create
      # and delete costs nothing and keeps behaviour identical everywhere.
      work_dir = File.tempname("docs_sandbox_work")
      Dir.mkdir_p(work_dir)

      # The container runs as an unprivileged fixed uid, which will not match
      # whoever owns these directories on the host. Without this the build
      # cannot write its own output, and on a machine where the runtime
      # silently remaps ownership the failure only appears somewhere else.
      # These are ephemeral directories we created and delete below.
      File.chmod(output_dir, 0o777)
      File.chmod(work_dir, 0o777)

      args = docker_args(source_dir, output_dir, work_dir)
      log_info "Building documentation under #{description}"

      output = IO::Memory.new
      status = Process.run(
        "docker",
        args,
        output: output,
        error: output,
        # Nothing from this process's environment reaches the container.
        # `docker` itself still needs the ambient PATH to be found.
        clear_env: false
      )

      unless status.success?
        return record_failure(explain(output.to_s))
      end

      # The compiler can exit 0 without writing anything useful, so the exit
      # status is never the whole story: the artifact has to parse.
      unless DocsSandbox.valid_docs_json?(File.join(output_dir, DOCS_JSON))
        return record_failure(
          "This shard compiled but produced no usable documentation.\n\n" \
          "crystal docs said:\n\n#{output.to_s.lines.last(40).join("\n")}"
        )
      end

      true
    rescue ex : IO::Error | RuntimeError
      raise DocsSandbox::Unavailable.new("Could not start the docker sandbox: #{ex.message}")
    ensure
      FileUtils.rm_rf(work_dir) if work_dir && Dir.exists?(work_dir)
    end

    private def docker_args(source_dir : String, output_dir : String, work_dir : String) : Array(String)
      [
        "run", "--rm",
        # No network namespace at all. A compile-time macro cannot reach the
        # internet, the cluster, or the host.
        "--network", network_mode,
        # Nothing on the container filesystem is writable except /tmp, the
        # scratch mount, and the output mount.
        "--read-only",
        # `noexec` is deliberately absent: `macro run` is a legitimate Crystal
        # feature that executes a compiled helper, and it is not a boundary
        # anyway, since confined code can already execute from its own scratch.
        "--tmpfs", "/tmp:rw,nosuid,size=256m,mode=1777",
        "-v", "#{work_dir}:#{WORK_DIR}:rw",
        # Ceilings: a hostile shard should not be able to exhaust the host.
        "--pids-limit", DocsSandbox.pids.to_s,
        "--memory", docker_memory,
        "--cpus", DocsSandbox.cpus,
        "--cap-drop", "ALL",
        "--security-opt", "no-new-privileges",
        "--user", "1000:1000",
        # The only variable the build gets. Note there is no `-e` passthrough
        # of the caller's environment, which is what keeps credentials out.
        "-e", "HOME=#{WORK_DIR}",
        "-v", "#{source_dir}:/src:ro",
        "-v", "#{output_dir}:/out:rw",
        "-w", WORK_DIR,
        DocsSandbox.image,
        "timeout", DocsSandbox.timeout_seconds.to_s,
        "sh", "-c", build_command,
      ]
    end

    # The source is copied out of the read-only mount because `crystal docs`
    # writes alongside the sources it reads. `--format=json` sends the
    # document to stdout rather than writing an HTML tree, so the shell
    # captures it into the output mount. That one file is the whole artifact:
    # we render documentation ourselves and never store shard-authored HTML.
    private def build_command : String
      "cp -r /src/. #{WORK_DIR}/ && cd #{WORK_DIR} && crystal docs --format=json > /out/#{DOCS_JSON}"
    end

    # Docker wants `2g`, Kubernetes quantities are written `2Gi`. Accept the
    # Kubernetes spelling everywhere so one setting configures both.
    private def docker_memory : String
      DocsSandbox.memory.downcase.sub(/i$/, "")
    end

    # Named rather than inlined above so the containment spec can run the very
    # same container with the network left in place. A spec that only shows
    # every probe failing proves nothing on its own, because a broken probe
    # and a working sandbox look identical from outside; the comparison is
    # what makes the word "blocked" a measurement. Production has no reason to
    # ever override this.
    protected def network_mode : String
      "none"
    end

    WORK_DIR = "/work"
  end
end
