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

      output = IO::Memory.new
      status = Process.run(
        "crystal",
        ["docs", "--output=#{output_dir}"],
        chdir: source_dir,
        output: output,
        error: output
      )

      unless status.success?
        log_error "Docs build failed: #{output.to_s.lines.last(20).join("\n")}"
        return false
      end

      true
    end
  end
end
