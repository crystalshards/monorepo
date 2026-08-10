module CrystalShards
  # Clones a repository, checks out a version, installs its dependencies and
  # runs `crystal docs` over the result.
  #
  # This is the whole shell-out surface of documentation building, extracted
  # from BuildDocsWorker so a spec can substitute a fake that never invokes
  # git, shards or crystal.
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

    # Populates `work_dir` from the repository and generates documentation.
    # Returns the directory holding the generated docs, or nil when the
    # `crystal docs` run failed or produced nothing.
    #
    # Raises when the repository cannot be cloned. A version that cannot be
    # checked out, or dependencies that cannot be installed, are not fatal:
    # the build falls back to whatever the clone produced.
    def generate_docs(repository_url : String, version : String, commit_sha : String?, work_dir : String) : String?
      clone_repository(repository_url, work_dir)
      checkout_version(work_dir, version, commit_sha)
      install_dependencies(work_dir)
      build_docs(work_dir)
    end

    private def clone_repository(repo_url : String, target_dir : String)
      cmd = "git clone --depth 1 #{repo_url} #{target_dir}"
      output = `#{cmd} 2>&1`

      unless $?.success?
        raise "Failed to clone repository: #{output}"
      end

      log_info "Cloned repository for docs build"
    end

    private def checkout_version(repo_dir : String, version : String, commit_sha : String?)
      if commit_sha
        cmd = "cd #{repo_dir} && git fetch --depth 1 origin #{commit_sha} && git checkout #{commit_sha}"
      else
        cmd = "cd #{repo_dir} && git fetch --depth 1 origin tag #{version} && git checkout #{version}"
      end

      output = `#{cmd} 2>&1`

      unless $?.success?
        log_info "Could not checkout specific version, using HEAD"
      end
    end

    private def install_dependencies(repo_dir : String)
      cmd = "cd #{repo_dir} && shards install --ignore-crystal-version 2>&1"
      output = `#{cmd}`

      if $?.success?
        log_info "Installed shard dependencies"
      else
        log_info "Could not install dependencies, continuing anyway: #{output}"
      end
    end

    private def build_docs(repo_dir : String) : String?
      docs_output = File.join(repo_dir, "docs")

      cmd = "cd #{repo_dir} && crystal docs --output=#{docs_output} 2>&1"
      output = `#{cmd}`

      unless $?.success?
        log_error "Failed to build docs: #{output}"
        return nil
      end

      unless Dir.exists?(docs_output)
        log_error "Docs directory not created"
        return nil
      end

      log_info "Built documentation successfully"
      docs_output
    end

    private def log_info(message : String)
      Log.info { "#{self.class.name}: #{message}" }
    end

    private def log_error(message : String)
      Log.error { "#{self.class.name}: #{message}" }
    end
  end
end
