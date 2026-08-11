require "../spec_helper"

# The docs build queue crosses a service boundary, and it crosses it untyped:
# this app serialises a task body that Cloud Tasks stores as opaque bytes and
# hands to a completely separate deployment. Nothing in either compiler run
# checks that the two sides agree on a field name.
#
# So the wire format is the contract, and these examples are the guard on it.
# If someone renames a field here, or the launcher renames one there, this is
# the only thing between that and builds that vanish into a 400 at three in
# the morning.
#
# Every example here is offline. Building the task and sending it are separate
# on purpose: a contract that can only be checked by dispatching a real task
# to Google is a contract nobody checks.
describe CrystalDocs::DocsBuildTask do
  it "carries package, version and build id, spelled as the launcher reads them" do
    parsed = JSON.parse(CrystalDocs::DocsBuildTask.new("kemal", "1.6.0", "build-7").to_json)

    parsed["package_name"].as_s.should eq("kemal")
    parsed["version"].as_s.should eq("1.6.0")
    parsed["build_id"].as_s.should eq("build-7")
  end
end

describe CrystalDocs::CloudTasksDocsBuildQueue do
  task = CrystalDocs::DocsBuildTask.new("kemal", "1.6.0", "build-7")

  body = ->do
    JSON.parse(
      CrystalDocs::CloudTasksDocsBuildQueue.task_json(
        "https://docs-launcher.example.run.app",
        "docs-tasks@example.iam.gserviceaccount.com",
        task
      )
    )["task"]["httpRequest"]
  end

  it "targets the launcher's build route with POST" do
    body.call["httpMethod"].as_s.should eq("POST")
    body.call["url"].as_s.should eq("https://docs-launcher.example.run.app/internal/docs/build")
  end

  # A trailing slash on the service URL would otherwise produce a double slash,
  # which Cloud Run does not route to the same action.
  it "joins the route cleanly when the launcher url has a trailing slash" do
    parsed = JSON.parse(
      CrystalDocs::CloudTasksDocsBuildQueue.task_json(
        "https://docs-launcher.example.run.app/",
        "docs-tasks@example.iam.gserviceaccount.com",
        task
      )
    )

    parsed["task"]["httpRequest"]["url"].as_s
      .should eq("https://docs-launcher.example.run.app/internal/docs/build")
  end

  # Cloud Tasks carries an HTTP body as bytes, so it arrives base64 encoded.
  # Asserting on the decoded value rather than the encoded blob is the point:
  # the launcher parses the decoded bytes.
  it "carries the build request as its body" do
    decoded = JSON.parse(Base64.decode_string(body.call["body"].as_s))

    decoded["package_name"].as_s.should eq("kemal")
    decoded["version"].as_s.should eq("1.6.0")
    decoded["build_id"].as_s.should eq("build-7")
  end

  it "declares the body as json so the launcher parses it" do
    body.call["headers"]["Content-Type"].as_s.should eq("application/json")
  end

  # Not optional. docs-launcher grants run.invoker to exactly one service
  # account, so a task without a token is a 403 on every single dispatch, and
  # the symptom is builds that never start rather than an error anyone sees.
  it "signs the task as the invoker the launcher accepts" do
    body.call["oidcToken"]["serviceAccountEmail"].as_s
      .should eq("docs-tasks@example.iam.gserviceaccount.com")
  end

  # The launcher verifies this audience. A token minted for a different
  # audience is a valid Google token for the wrong service and must not open
  # this door.
  it "mints the token for the launcher's own audience" do
    body.call["oidcToken"]["audience"].as_s
      .should eq("https://docs-launcher.example.run.app")
  end

  describe "#enqueue" do
    it "sends one task to the configured queue and returns the build id" do
      sent = [] of {String, String}
      original = CrystalDocs::CloudTasksDocsBuildQueue.transport

      CrystalDocs::CloudTasksDocsBuildQueue.transport = ->(queue_path : String, task_json : String) {
        sent << {queue_path, task_json}
        nil
      }

      begin
        with_cloud_tasks_env do
          build_id = CrystalDocs::CloudTasksDocsBuildQueue.new.enqueue("kemal", "1.6.0")

          sent.size.should eq(1)
          sent.first[0].should eq("projects/test-project/locations/us-central1/queues/docs-builds")

          decoded = JSON.parse(
            Base64.decode_string(
              JSON.parse(sent.first[1])["task"]["httpRequest"]["body"].as_s
            )
          )

          # The id returned is the id recorded against the request row, and the
          # id the launcher logs. If these ever diverge, a stuck build cannot
          # be traced from a docs page to an execution.
          decoded["build_id"].as_s.should eq(build_id)
          decoded["package_name"].as_s.should eq("kemal")
        end
      ensure
        CrystalDocs::CloudTasksDocsBuildQueue.transport = original
      end
    end

    # A docs page must render even when the queue is unreachable. Returning nil
    # leaves the row pending with no build id, which is visible in the data.
    it "returns nil rather than raising when the queue cannot be reached" do
      original = CrystalDocs::CloudTasksDocsBuildQueue.transport

      CrystalDocs::CloudTasksDocsBuildQueue.transport = ->(_q : String, _t : String) {
        raise "Cloud Tasks is unreachable"
      }

      begin
        with_cloud_tasks_env do
          CrystalDocs::CloudTasksDocsBuildQueue.new.enqueue("kemal", "1.6.0").should be_nil
        end
      ensure
        CrystalDocs::CloudTasksDocsBuildQueue.transport = original
      end
    end

    # Missing configuration must not be papered over with a default. A wrong
    # queue silently drops every build.
    it "refuses to enqueue when the launcher url is unset" do
      original = CrystalDocs::CloudTasksDocsBuildQueue.transport
      sent = 0

      CrystalDocs::CloudTasksDocsBuildQueue.transport = ->(_q : String, _t : String) {
        sent += 1
        nil
      }

      begin
        with_cloud_tasks_env(launcher_url: nil) do
          CrystalDocs::CloudTasksDocsBuildQueue.new.enqueue("kemal", "1.6.0").should be_nil
        end

        sent.should eq(0)
      ensure
        CrystalDocs::CloudTasksDocsBuildQueue.transport = original
      end
    end
  end
end

describe CrystalDocs::InProcessDocsBuildQueue do
  # Development and test must not need a broker or a Google project.
  it "returns a build id without reaching anything" do
    CrystalDocs::InProcessDocsBuildQueue.new.enqueue("kemal", "1.6.0").should_not be_nil
  end
end

describe CrystalDocs::DocsBuildQueue do
  it "builds the in-process queue outside production" do
    CrystalDocs::DocsBuildQueue.override = nil

    CrystalDocs::DocsBuildQueue.build.should be_a(CrystalDocs::InProcessDocsBuildQueue)
  end

  it "uses the override when one is installed" do
    queue = RecordingBuildQueue.install

    CrystalDocs::DocsBuildQueue.build.should be(queue)
  end
end
