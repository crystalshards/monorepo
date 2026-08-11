module CrystalShards
  # Runs the compile in this process, with no confinement whatsoever.
  #
  # Reaching this class means someone set DOCS_SANDBOX_ALLOW_UNSAFE=true. It
  # exists so a developer without Docker can still work on the surrounding
  # code, and for nothing else: a shard's macros run here with this process's
  # environment, network and filesystem. It logs loudly for that reason.
  class UnsandboxedDocsSandbox < DocsSandbox
    def description : String
      "NO SANDBOX, untrusted code runs in this process"
    end

    def build_docs(source_dir : String, output_dir : String) : Bool
      log_error "Building documentation with no sandbox. Shard macros execute " \
                "with this process's environment and network. Never do this " \
                "where real credentials are present."

      Dir.mkdir_p(output_dir)
      docs_json = File.join(output_dir, DOCS_JSON)

      # `--format=json` writes the document to stdout. Stream it straight
      # into the artifact file instead of buffering a whole program's worth
      # of JSON in memory.
      error = IO::Memory.new
      status = File.open(docs_json, "w") do |stdout|
        Process.run(
          "crystal",
          ["docs", "--format=json"],
          chdir: source_dir,
          output: stdout,
          error: error
        )
      end

      unless status.success?
        log_error "Docs build failed: #{error.to_s.lines.last(20).join("\n")}"
      end

      # The compiler can exit 0 having written nothing useful, so success is
      # a parseable, non-empty docs.json, never the exit status alone. A
      # failed attempt leaves nothing behind, or a later check could mistake
      # a stale or partial file for a real build.
      unless status.success? && DocsSandbox.valid_docs_json?(docs_json)
        File.delete(docs_json) if File.exists?(docs_json)
        return false
      end

      true
    end
  end
end
