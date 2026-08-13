require "../spec_helper"

# What the launcher does when it cannot read the status of a build it started.
#
# Not hypothetical. roles/run.jobsExecutorWithOverrides lets the launcher START
# the docs-build Job, and starting with overrides returns a long-running
# operation rather than an execution. Reading that operation needs
# run.operations.get, which the role does not carry and which cannot be granted
# on the Job: an operation lives at projects/<p>/locations/<r>/operations/<id>
# and is not addressable underneath the Job that produced it.
#
# So the launcher started builds it could not watch. Every poll came back 403,
# and the loop retried it until the sandbox deadline, which in the logs reads
# like a slow build rather than a missing grant, while holding the Cloud Tasks
# request open against a service with a small concurrency cap.
#
# The grant is fixed in terraform. These pin the behaviour that made it so hard
# to see, and the retrying that has to survive next to it.

# A scratch store that answers any download with a valid docs.json. The object
# key carries a random build id, so a spec cannot pre-seed it, and the artifact
# only exists in reality because the build wrote it through a signed PUT this
# double does not serve.
private class AlwaysAnswersScratch < CrystalShards::MockScratchStorage
  def download_scratch(key : String) : String
    %({"repository_name":"spec","program":{"full_name":"spec","name":"spec"}})
  end
end

private def with_cloud_run_sandbox(
  polls : Array({Int32, String}),
  storage : CrystalShards::MockScratchStorage = CrystalShards::MockScratchStorage.new,
  &
)
  # The sandbox refuses to start without knowing which Job it runs, which is
  # its own guard and not what these exercise.
  previous = {
    "GOOGLE_CLOUD_PROJECT"  => ENV["GOOGLE_CLOUD_PROJECT"]?,
    "DOCS_BUILD_JOB"        => ENV["DOCS_BUILD_JOB"]?,
    "DOCS_BUILD_JOB_REGION" => ENV["DOCS_BUILD_JOB_REGION"]?,
  }
  ENV["GOOGLE_CLOUD_PROJECT"] = "spec-project"
  ENV["DOCS_BUILD_JOB"] = "docs-build"
  ENV["DOCS_BUILD_JOB_REGION"] = "us-central1"

  sandbox = CrystalShards::CloudRunJobDocsSandbox.new(storage)
  calls = 0

  CrystalShards::CloudRunJobDocsSandbox.runner = ->(build_id : String, _body : String) {
    "projects/spec/locations/us-central1/operations/#{build_id}"
  }

  CrystalShards::CloudRunJobDocsSandbox.poller = ->(_operation : String) {
    poll = polls[Math.min(calls, polls.size - 1)]
    calls += 1
    poll
  }

  source = File.tempname("docs_source_spec")
  output = File.tempname("docs_output_spec")
  Dir.mkdir_p(source)
  File.write(File.join(source, "shard.yml"), "name: spec\nversion: 0.1.0\n")

  yield sandbox, source, output, -> { calls }
ensure
  CrystalShards::CloudRunJobDocsSandbox.runner = nil
  CrystalShards::CloudRunJobDocsSandbox.poller = nil
  FileUtils.rm_rf(source) if source
  FileUtils.rm_rf(output) if output

  # Restored rather than deleted: a leaked value would make a later example
  # pass against a configuration it did not choose.
  previous.try &.each do |key, value|
    if value
      ENV[key] = value
    else
      ENV.delete(key)
    end
  end
end

describe CrystalShards::CloudRunJobDocsSandbox do
  describe "execution overrides" do
    it "passes the complete core compiler recipe to the build container" do
      storage = CrystalShards::MockScratchStorage.new
      sandbox = CrystalShards::CloudRunJobDocsSandbox.new(
        storage,
        job_env: CrystalShards::CoreDocs::JOB_ENV,
        crystal_path: CrystalShards::CoreDocs::CRYSTAL_PATH,
        entry_file: CrystalShards::CoreDocs::ENTRY_FILE,
        project_name: CrystalShards::CoreDocs::PROJECT_NAME,
        project_version: "1.21.0",
      )

      request = JSON.parse(sandbox.execution_request("source.tar.gz", "docs.json", "build.log"))
      entries = request["overrides"]["containerOverrides"][0]["env"].as_a
      env = {} of String => String
      entries.each { |entry| env[entry["name"].as_s] = entry["value"].as_s }

      env["DOCS_CRYSTAL_PATH"].should eq("lib:src")
      env["DOCS_ENTRY_FILE"].should eq("src/docs_main.cr")
      env["DOCS_PROJECT_NAME"].should eq("Crystal")
      env["DOCS_PROJECT_VERSION"].should eq("1.21.0")
    end
  end

  describe "reading the status of a build it started" do
    it "stops on a refusal rather than retrying an answer that cannot change" do
      refusal = {403, %({"error":{"message":"Permission 'run.operations.get' denied"}})}

      with_cloud_run_sandbox([refusal]) do |sandbox, source, output, calls|
        # Reported as a failed build: something did start, and we can no longer
        # say what it did.
        sandbox.build_docs(source, output).should be_false

        # The point. One attempt, not one every couple of seconds until the
        # deadline: the launcher polls with its own identity, so a refusal is
        # the same answer every time.
        calls.call.should eq(1)
      end
    end

    it "stops on an unauthenticated response the same way" do
      unauthenticated = {401, %({"error":{"message":"invalid authentication credentials"}})}

      with_cloud_run_sandbox([unauthenticated]) do |sandbox, source, output, calls|
        sandbox.build_docs(source, output).should be_false
        calls.call.should eq(1)
      end
    end

    # The behaviour that must not be lost while fixing the above. A 500 is not
    # an answer about the build, and calling it a failure would mark a shard
    # broken over something on our side, after which the retry floor refuses to
    # reconsider it.
    it "keeps polling through a server error and succeeds when the build does" do
      polls = [
        {500, "upstream hiccup"},
        {200, %({"done":false})},
        {200, %({"done":true})},
      ] of {Int32, String}

      with_cloud_run_sandbox(polls, storage: AlwaysAnswersScratch.new) do |sandbox, source, output, calls|
        sandbox.build_docs(source, output).should be_true

        # Three: the refused-looking 500, the not-done, then done. Neither of
        # the first two is an answer about the build.
        calls.call.should eq(3)
      end
    end
  end
end
