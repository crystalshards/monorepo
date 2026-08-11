require "../spec_helper"

# Documentation is built the first time a version is asked for, so this
# service is the thing standing between a cold URL and the build queue. Every
# example here is about how many builds get commissioned, because that is the
# property that matters: too few and the page never fills in, too many and any
# stranger with a URL bar can spend our compute.
describe CrystalDocs::DocBuildRequests do
  requests = ->(queue : CrystalDocs::DocsBuildQueue) {
    CrystalDocs::DocBuildRequests.new(queue)
  }

  describe "a version nobody has asked for" do
    it "registers it and queues exactly one build" do
      queue = RecordingBuildQueue.new

      request = requests.call(queue).request("kemal", "1.6.0")

      request.package_name.should eq("kemal")
      request.version.should eq("1.6.0")
      request.status.should eq(DocBuildRequest::PENDING)
      request.attempts.should eq(1)
      queue.count_for("kemal", "1.6.0").should eq(1)
    end

    it "records the queued job id, so a stuck build is traceable" do
      queue = RecordingBuildQueue.new

      request = requests.call(queue).request("kemal", "1.6.0")

      request.job_id.should eq("job-1")
    end
  end

  # The acceptance case. Nothing caches a miss, so this runs on every page
  # view of an unbuilt version.
  describe "repeated cold requests" do
    it "creates one build request and queues one build" do
      queue = RecordingBuildQueue.new
      service = requests.call(queue)

      5.times { service.request("kemal", "1.6.0") }

      DocBuildRequestQuery.new.package_name("kemal").version("1.6.0").select_count.should eq(1)
      queue.count_for("kemal", "1.6.0").should eq(1)
    end

    it "keeps attempts at one, so the retry counter measures retries" do
      queue = RecordingBuildQueue.new
      service = requests.call(queue)

      3.times { service.request("kemal", "1.6.0") }

      service.find("kemal", "1.6.0").not_nil!.attempts.should eq(1)
    end

    # The reason the insert is ON CONFLICT rather than a read followed by a
    # write. Several readers landing on the same cold version at once is the
    # normal way a popular unbuilt version gets discovered, and a
    # check-then-insert loses exactly there.
    it "queues one build even when the requests are concurrent" do
      queue = RecordingBuildQueue.new
      callers = 8
      done = Channel(Nil).new

      callers.times do
        spawn do
          begin
            requests.call(queue).request("kemal", "1.6.0")
          ensure
            done.send(nil)
          end
        end
      end

      callers.times { done.receive }

      DocBuildRequestQuery.new.package_name("kemal").version("1.6.0").select_count.should eq(1)
      queue.count_for("kemal", "1.6.0").should eq(1)
    end
  end

  describe "a version that is already built" do
    it "queues nothing" do
      queue = RecordingBuildQueue.new
      DocBuildRequestFactory.create &.package_name("kemal").version("1.6.0").succeeded

      requests.call(queue).request("kemal", "1.6.0")

      queue.enqueued.should be_empty
    end

    it "leaves the succeeded row alone" do
      queue = RecordingBuildQueue.new
      finished = 3.hours.ago
      DocBuildRequestFactory.create &.package_name("kemal").version("1.6.0").succeeded(finished)

      request = requests.call(queue).request("kemal", "1.6.0")

      request.status.should eq(DocBuildRequest::SUCCEEDED)
      request.attempts.should eq(1)
    end
  end

  describe "a version whose build is already in flight" do
    it "queues nothing for a pending request" do
      queue = RecordingBuildQueue.new
      DocBuildRequestFactory.create &.package_name("kemal").version("1.6.0")

      requests.call(queue).request("kemal", "1.6.0")

      queue.enqueued.should be_empty
    end

    it "queues nothing while a worker is building" do
      queue = RecordingBuildQueue.new
      DocBuildRequestFactory.create &.package_name("kemal").version("1.6.0")
        .status(DocBuildRequest::BUILDING)
        .started_at(1.minute.ago)

      requests.call(queue).request("kemal", "1.6.0")

      queue.enqueued.should be_empty
    end
  end

  # Without a floor, every visitor to a package that cannot build re-queues
  # it, and one permanently broken shard with a trickle of traffic starves the
  # queue for shards that would succeed.
  describe "the retry floor after a failure" do
    it "does not re-queue a build that just failed" do
      queue = RecordingBuildQueue.new
      DocBuildRequestFactory.create &.package_name("kemal").version("1.6.0").failed(1.minute.ago)

      requests.call(queue).request("kemal", "1.6.0")

      queue.enqueued.should be_empty
    end

    it "does not re-queue however many times the page is reloaded" do
      queue = RecordingBuildQueue.new
      DocBuildRequestFactory.create &.package_name("kemal").version("1.6.0").failed(5.minutes.ago)
      service = requests.call(queue)

      10.times { service.request("kemal", "1.6.0") }

      queue.enqueued.should be_empty
    end

    it "keeps the failure visible rather than resetting it to pending" do
      queue = RecordingBuildQueue.new
      DocBuildRequestFactory.create &.package_name("kemal").version("1.6.0")
        .failed(1.minute.ago, "undefined constant Foo")

      request = requests.call(queue).request("kemal", "1.6.0")

      request.status.should eq(DocBuildRequest::FAILED)
      request.last_error.should eq("undefined constant Foo")
      request.failed_at.should_not be_nil
    end

    it "still refuses a minute before the floor" do
      queue = RecordingBuildQueue.new
      DocBuildRequestFactory.create &.package_name("kemal").version("1.6.0")
        .failed(CrystalDocs::DocBuildRequests::RETRY_FLOOR.ago + 1.minute)

      requests.call(queue).request("kemal", "1.6.0")

      queue.enqueued.should be_empty
    end

    it "queues one build once the floor has passed" do
      queue = RecordingBuildQueue.new
      DocBuildRequestFactory.create &.package_name("kemal").version("1.6.0")
        .failed(CrystalDocs::DocBuildRequests::RETRY_FLOOR.ago - 1.minute)

      request = requests.call(queue).request("kemal", "1.6.0")

      queue.count_for("kemal", "1.6.0").should eq(1)
      request.status.should eq(DocBuildRequest::PENDING)
      request.attempts.should eq(2)
    end

    it "clears the previous failure when it retries" do
      queue = RecordingBuildQueue.new
      DocBuildRequestFactory.create &.package_name("kemal").version("1.6.0")
        .failed(2.hours.ago, "undefined constant Foo")

      request = requests.call(queue).request("kemal", "1.6.0")

      request.failed_at.should be_nil
      request.last_error.should be_nil
    end

    # A retry is a fresh race: several readers arrive after the floor has
    # passed and the same UPDATE has to pick one winner.
    it "queues one build when the retry is concurrent" do
      queue = RecordingBuildQueue.new
      DocBuildRequestFactory.create &.package_name("kemal").version("1.6.0")
        .failed(2.hours.ago)

      done = Channel(Nil).new
      6.times do
        spawn do
          begin
            requests.call(queue).request("kemal", "1.6.0")
          ensure
            done.send(nil)
          end
        end
      end
      6.times { done.receive }

      queue.count_for("kemal", "1.6.0").should eq(1)
    end
  end

  describe "when the queue cannot be reached" do
    it "still registers the version rather than losing the request" do
      queue = RecordingBuildQueue.new
      queue.available = false

      request = requests.call(queue).request("kemal", "1.6.0")

      request.status.should eq(DocBuildRequest::PENDING)
    end

    it "records no job id, so the row does not claim a build that was never queued" do
      queue = RecordingBuildQueue.new
      queue.available = false

      request = requests.call(queue).request("kemal", "1.6.0")

      request.job_id.should be_nil
    end
  end

  describe "different versions of the same package" do
    it "are built independently" do
      queue = RecordingBuildQueue.new
      service = requests.call(queue)

      service.request("kemal", "1.6.0")
      service.request("kemal", "1.7.0")

      queue.count_for("kemal", "1.6.0").should eq(1)
      queue.count_for("kemal", "1.7.0").should eq(1)
    end
  end
end
