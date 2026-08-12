require "../spec_helper"

# A claim nobody ever resolved.
#
# The retry path matched only on 'failed', so a request whose task was never
# delivered, or whose builder died before writing an outcome, stayed claimed
# forever. Every reader afterwards was told the documentation was being built,
# and no build was happening or ever would.
#
# This is not a hypothetical failure mode. It is the state the entire published
# catalogue was left in: rows claimed while the launcher could not authenticate,
# then the launcher fixed, and not one row moved, because nothing reconsiders a
# claim.
private def planted(status : String, claimed_at : Time, package_name : String = "stale-pkg")
  AppDatabase.exec(
    "INSERT INTO doc_build_requests " \
    "(package_name, version, status, requested_at, started_at, attempts, created_at, updated_at) " \
    "VALUES ($1, '1.0.0', $2, $3, $4, 1, $3, $3)",
    package_name,
    status,
    claimed_at,
    status == "building" ? claimed_at : nil
  )
end

private def status_of(package_name : String) : String
  CrystalDocs::DocBuildRequests.new.find(package_name, "1.0.0").not_nil!.status
end

describe CrystalDocs::DocBuildRequests do
  describe "a claim that never resolved" do
    it "is queued again once it is older than a build could possibly be" do
      planted("pending", Time.utc - CrystalDocs::DocBuildRequests::STALE_CLAIM_FLOOR - 1.minute)
      queue = RecordingBuildQueue.install

      CrystalDocs::DocBuildRequests.new(queue).request("stale-pkg", "1.0.0")

      queue.count_for("stale-pkg", "1.0.0").should eq(1)
    end

    it "recovers a build that died after starting, not just an undelivered one" do
      planted("building", Time.utc - CrystalDocs::DocBuildRequests::STALE_CLAIM_FLOOR - 1.minute)
      queue = RecordingBuildQueue.install

      CrystalDocs::DocBuildRequests.new(queue).request("stale-pkg", "1.0.0")

      queue.count_for("stale-pkg", "1.0.0").should eq(1)
      status_of("stale-pkg").should eq("pending")
    end

    # The half that keeps this safe. The floor sits beyond the longest a build
    # can legitimately take, so a build still running is never re-queued
    # underneath itself, and a page refreshing every few seconds does not
    # commission a build per view.
    it "leaves a fresh claim alone" do
      planted("building", Time.utc - 2.minutes)
      queue = RecordingBuildQueue.install

      CrystalDocs::DocBuildRequests.new(queue).request("stale-pkg", "1.0.0")

      queue.count_for("stale-pkg", "1.0.0").should eq(0)
      status_of("stale-pkg").should eq("building")
    end

    it "still leaves a succeeded row alone however old it is" do
      planted("succeeded", Time.utc - 30.days)
      queue = RecordingBuildQueue.install

      CrystalDocs::DocBuildRequests.new(queue).request("stale-pkg", "1.0.0")

      queue.count_for("stale-pkg", "1.0.0").should eq(0)
      status_of("stale-pkg").should eq("succeeded")
    end
  end
end
