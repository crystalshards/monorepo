require "./docs_sandbox"

module CrystalShards
  # Produces documentation for a shard.
  #
  # The work is deliberately split in two, because only half of it is
  # dangerous:
  #
  #   Trusted phase   cloning the repository and fetching dependencies. Needs
  #                   the network. Executes no code from the shard, as long as
  #                   postinstall hooks stay disabled.
  #
  #   Untrusted phase `crystal docs`. Needs no network. Executes code from the
  #                   shard, because Crystal expands macros while compiling and
  #                   a macro can shell out. This phase is handed to a
  #                   DocsSandbox and never runs in this process.
  #
  # Keeping those apart is what stops a published shard from reading the
  # storage and database credentials this worker holds.
  class DocsBuilder
    # Test seam. When set, `build` returns this proc's result instead of a real
    # builder. Always nil in production.
    class_property builder : Proc(DocsBuilder)? = nil

    def self.build : DocsBuilder
      if custom = @@builder
        custom.call
      else
        new
      end
    end

    # The sandbox is resolved when a build actually starts, not here.
    # Constructing a builder is harmless; compiling someone else's code is the
    # part that needs confinement, so that is where the refusal belongs.
    def initialize(@sandbox : DocsSandbox? = nil)
    end

    private def sandbox : DocsSandbox
      @sandbox ||= DocsSandbox.build
    end

    # Populates `work_dir` from the repository and generates documentation.
    # Returns the path to the generated docs.json, or nil when the build
    # failed or produced nothing usable.
    #
    # Raises when the repository cannot be cloned, or when no sandbox is
    # available: refusing to build is correct, building unconfined is not.
    # A version that cannot be checked out, or dependencies that cannot be
    # installed, are not fatal: the build falls back to whatever the clone
    # produced, which is how most shards without lockfiles still document.
    def generate_docs(repository_url : String, version : String, commit_sha : String?, work_dir : String) : String?
      # Resolve the sandbox before doing any work. If we are not allowed to
      # compile this safely then cloning first would spend network and disk to
      # arrive at the same refusal.
      active = sandbox

      # Read the compiler version off the sandbox before spending a clone. A
      # misconfigured image is a configuration error, and it should say so
      # rather than surface as a dependency resolution that quietly used the
      # wrong compiler.
      compiler = active.crystal_version

      source_dir = File.join(work_dir, "source")
      docs_dir = File.join(work_dir, "docs")

      Dir.mkdir_p(source_dir)

      clone_repository(repository_url, source_dir)
      checkout_version(source_dir, version, commit_sha)
      install_dependencies(source_dir, compiler)

      build_docs(active, source_dir, docs_dir)
    end

    private def clone_repository(repo_url : String, target_dir : String)
      status = run("git", ["clone", "--depth", "1", repo_url, target_dir])

      unless status[:success]
        raise "Failed to clone repository: #{status[:output]}"
      end

      log_info "Cloned repository for docs build"
    end

    # A checkout that cannot reach the requested ref is fatal, not a warning.
    # Falling back to HEAD produced an artifact labelled with a version it was
    # not built from, which is worse than having no documentation: every
    # signature, every type and every cross link would describe a different
    # release while claiming to be this one.
    private def checkout_version(repo_dir : String, version : String, commit_sha : String?)
      args = if commit_sha
               ["fetch", "--depth", "1", "origin", commit_sha]
             else
               ["fetch", "--depth", "1", "origin", "tag", version]
             end

      run("git", args, chdir: repo_dir)
      target = commit_sha || version

      unless run("git", ["checkout", target], chdir: repo_dir)[:success]
        raise "Could not check out #{target}, refusing to document a different revision as #{version}"
      end

      # `git checkout` reporting success is not the same as being on the
      # revision we asked for. When the caller named an exact commit, confirm
      # the working tree really is that commit before anything gets compiled
      # and published under this version's name.
      if commit_sha
        landed = resolved_commit(repo_dir)

        unless landed && landed.starts_with?(commit_sha[0, {commit_sha.size, landed.size}.min])
          raise "Checked out #{landed.inspect} but #{commit_sha.inspect} was requested for #{version}"
        end
      end
    end

    # The commit actually built, recorded so an artifact can be traced back to
    # a revision rather than to a tag, which can be moved after the fact.
    private def resolved_commit(repo_dir : String) : String?
      status = run("git", ["rev-parse", "HEAD"], chdir: repo_dir)
      status[:success] ? status[:output].strip.presence : nil
    end

    # `--skip-postinstall` is load bearing, not tidiness. A postinstall hook is
    # a command the shard author chose, and this phase still holds the worker's
    # environment, so running hooks here would reintroduce exactly the hole the
    # sandbox closes.
    #
    # CRYSTAL_VERSION is what stops shards shelling out to `crystal`. Having
    # written the lock, shards runs the compiler once purely to read its
    # version, and this image has no compiler in it: the whole install then
    # exits 1 having already done its work. The value comes from the sandbox
    # rather than from configuration of its own, because dependencies must
    # resolve for the compiler that is going to compile them, and two settings
    # would be two things to keep in step with nothing able to enforce it.
    #
    # A failed install is fatal, where it used to be logged and stepped over.
    # Continuing meant compiling whatever tree shards abandoned, and a partial
    # lib/ that still compiles publishes documentation quietly missing
    # whatever it could not resolve. Wrong documentation under a version's
    # name is worse than none: nothing on the page says it is incomplete, and
    # the failure surfaces later as a compile error nobody can trace back to a
    # fetch.
    private def install_dependencies(repo_dir : String, crystal_version : String)
      status = run("shards",
        ["install", "--skip-postinstall", "--skip-executables", "--ignore-crystal-version"],
        chdir: repo_dir,
        env: {"CRYSTAL_VERSION" => crystal_version})

      unless status[:success]
        raise "Could not install dependencies, so there is no complete tree to document: #{status[:output]}"
      end

      log_info "Installed shard dependencies"
    end

    private def build_docs(active : DocsSandbox, source_dir : String, docs_dir : String) : String?
      log_info "Handing the compile to the sandbox: #{active.description}"

      unless active.build_docs(source_dir, docs_dir)
        log_error "Sandboxed documentation build failed"
        return nil
      end

      # The sandboxes already refuse a missing or unparseable artifact; this
      # is the same contract at the hand-off, so a custom DocsSandbox cannot
      # silently downgrade it.
      docs_json = File.join(docs_dir, DocsSandbox::DOCS_JSON)
      unless DocsSandbox.valid_docs_json?(docs_json)
        log_error "Sandbox produced no usable #{DocsSandbox::DOCS_JSON}"
        return nil
      end

      log_info "Built documentation successfully"
      docs_json
    end

    # Arguments are passed as an array rather than interpolated into a shell
    # string. Repository URLs and version tags come from the registry, so a
    # name containing shell metacharacters must not become a command.
    # `env` adds to this process's environment rather than replacing it: git
    # and shards both need PATH, HOME and the ambient proxy settings to work
    # at all, so clearing it would break the fetch this phase exists to do.
    private def run(command : String, args : Array(String), chdir : String? = nil, env : Process::Env = nil)
      output = IO::Memory.new
      status = Process.run(command, args, chdir: chdir, env: env, output: output, error: output)
      {success: status.success?, output: output.to_s}
    end

    private def log_info(message : String)
      Log.info { "#{self.class.name}: #{message}" }
    end

    private def log_error(message : String)
      Log.error { "#{self.class.name}: #{message}" }
    end
  end
end
