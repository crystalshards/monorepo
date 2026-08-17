module CrystalDocs
  # What a running documentation build is doing, for the reader watching it.
  #
  # A build clones a repository, checks out a version, installs dependencies,
  # runs the compiler in a sandbox and uploads the result. On a large shard
  # that is minutes, and the page said "the build is running" for all of it,
  # which reads the same as a stuck queue. These are the same minutes either
  # way; the difference is whether the reader can see them pass.
  #
  # crystalshards is the writer. Its copy of these names is
  # `CrystalShards::DocsBuildStatus::Step`, and the two lists have to agree.
  # They are strings in a column rather than a shared type because the two
  # apps are separate deployments with no common code.
  module BuildSteps
    record Step, name : String, label : String, description : String

    # In the order the builder performs them, which is the order they are
    # rendered in. `DocsBuilder#generate_docs` runs the first four and
    # `BuildDocsWorker` performs the fifth.
    ALL = [
      Step.new("cloning", "Cloning", "Fetching the repository."),
      Step.new("resolving", "Resolving version", "Finding the commit this version points at."),
      Step.new("dependencies", "Installing dependencies", "Fetching the shards it depends on."),
      Step.new("documenting", "Extracting the API", "Running the compiler in a sandbox."),
      Step.new("uploading", "Publishing", "Storing the generated documentation."),
    ]

    # Nil when nothing has been reported yet, which is the normal state for the
    # first seconds of a build and the permanent state of a build whose step
    # writes were all lost. Callers render the list without a current step
    # rather than inventing one.
    def self.index_of(name : String?) : Int32?
      return nil if name.nil?

      ALL.index { |step| step.name == name }
    end

    # A name this app does not know is shown rather than dropped. The writer is
    # a separate deployment and can be ahead of this one; a reader seeing an
    # unfamiliar but honest word is better than a progress list that silently
    # claims the build is somewhere it is not.
    def self.label_for(name : String?) : String?
      return nil if name.nil?

      ALL.find { |step| step.name == name }.try(&.label) || name
    end
  end
end
