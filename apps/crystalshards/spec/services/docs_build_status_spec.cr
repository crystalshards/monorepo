require "../spec_helper"

# The one thing this app tells the documentation site, against a real second
# database. It had no coverage at all: nothing in this suite touched
# DocsDatabase, the tables did not exist in test, every write raised "relation
# does not exist", and the writer swallowed it. That is how build_status stayed
# 'pending' for the whole catalogue with a green suite on both sides.
describe CrystalShards::DocsBuildStatus do
  describe "#succeeded" do
    it "moves the request row and the version row together" do
      DocsRows.register("github.com/user/pkg", "1.0.0")
      DocsRows.request("github.com/user/pkg", "1.0.0")

      CrystalShards::DocsBuildStatus.new("github.com/user/pkg", "1.0.0").succeeded

      DocsRows.request_status("github.com/user/pkg", "1.0.0").should eq("succeeded")
      DocsRows.version_status("github.com/user/pkg", "1.0.0").should eq("success")
    end

    it "clears the failure of an earlier attempt" do
      DocsRows.register("github.com/user/retried", "2.0.0")
      DocsRows.request("github.com/user/retried", "2.0.0")
      status = CrystalShards::DocsBuildStatus.new("github.com/user/retried", "2.0.0")

      status.failed("the first attempt did not compile")
      status.succeeded

      outcome = DocsRows.request_outcome("github.com/user/retried", "2.0.0")
      outcome.status.should eq("succeeded")
      outcome.finished_at.should_not be_nil
      # crystaldocs measures its one hour retry floor from failed_at, so a
      # success that left it set would keep refusing to rebuild a version that
      # is now fine.
      outcome.failed_at.should be_nil
      outcome.last_error.should be_nil
      DocsRows.version_status("github.com/user/retried", "2.0.0").should eq("success")
    end

    # The case the request table cannot answer, and the reason doc_versions is
    # written at all: the registry indexer commissions builds nobody asked for
    # from a page, so most of the catalogue has no request row.
    it "records a build that has no request row" do
      DocsRows.register("github.com/user/unrequested", "0.1.0")

      CrystalShards::DocsBuildStatus.new("github.com/user/unrequested", "0.1.0").succeeded

      DocsRows.version_status("github.com/user/unrequested", "0.1.0").should eq("success")
    end

    it "records nothing for a version crystaldocs has never registered" do
      # No rows anywhere. Both statements match nothing, which is a successful
      # write of nothing and must not raise.
      CrystalShards::DocsBuildStatus.new("github.com/user/unknown", "9.9.9").succeeded

      DocsDatabase.query_one("SELECT COUNT(*) FROM doc_versions", as: Int64).should eq(0)
    end

    it "leaves another version of the same package alone" do
      DocsRows.register("github.com/user/multi", "1.0.0")
      DocsRows.register("github.com/user/multi", "2.0.0")

      CrystalShards::DocsBuildStatus.new("github.com/user/multi", "2.0.0").succeeded

      DocsRows.version_status("github.com/user/multi", "1.0.0").should eq("pending")
      DocsRows.version_status("github.com/user/multi", "2.0.0").should eq("success")
    end
  end

  describe "#failed" do
    it "moves the request row and the version row together" do
      DocsRows.register("github.com/user/broken", "1.0.0")
      DocsRows.request("github.com/user/broken", "1.0.0")

      CrystalShards::DocsBuildStatus.new("github.com/user/broken", "1.0.0")
        .failed("crystal docs: undefined constant Foo")

      outcome = DocsRows.request_outcome("github.com/user/broken", "1.0.0")
      outcome.status.should eq("failed")
      outcome.failed_at.should_not be_nil
      outcome.last_error.should eq("crystal docs: undefined constant Foo")
      DocsRows.version_status("github.com/user/broken", "1.0.0").should eq("failed")
    end

    it "records a reason when the build did not give one" do
      DocsRows.register("github.com/user/silent", "1.0.0")
      DocsRows.request("github.com/user/silent", "1.0.0")

      CrystalShards::DocsBuildStatus.new("github.com/user/silent", "1.0.0").failed(nil)

      DocsRows.request_outcome("github.com/user/silent", "1.0.0")
        .last_error.should eq("The build failed without reporting a reason.")
    end

    # The page shows this verbatim, and a shard that does not compile can
    # produce tens of kilobytes of it.
    it "caps a very long reason at the useful end" do
      DocsRows.register("github.com/user/verbose", "1.0.0")
      DocsRows.request("github.com/user/verbose", "1.0.0")
      reason = "error: #{"x" * 8000}"

      CrystalShards::DocsBuildStatus.new("github.com/user/verbose", "1.0.0").failed(reason)

      stored = DocsRows.request_outcome("github.com/user/verbose", "1.0.0").last_error.not_nil!
      stored.size.should eq(CrystalShards::DocsBuildStatus::MAX_ERROR_LENGTH + "\n... truncated".size)
      stored.should start_with("error: xxx")
      stored.should end_with("\n... truncated")
    end
  end

  describe "#building" do
    it "moves the request row and the version row together" do
      DocsRows.register("github.com/user/started", "1.0.0")
      DocsRows.request("github.com/user/started", "1.0.0")

      CrystalShards::DocsBuildStatus.new("github.com/user/started", "1.0.0").building

      outcome = DocsRows.request_outcome("github.com/user/started", "1.0.0")
      outcome.status.should eq("building")
      outcome.started_at.should_not be_nil
      DocsRows.version_status("github.com/user/started", "1.0.0").should eq("building")
    end

    it "clears the previous attempt's failure so the page stops showing it" do
      DocsRows.register("github.com/user/rebuilt", "1.0.0")
      DocsRows.request("github.com/user/rebuilt", "1.0.0")
      status = CrystalShards::DocsBuildStatus.new("github.com/user/rebuilt", "1.0.0")

      status.failed("first attempt failed")
      status.building

      outcome = DocsRows.request_outcome("github.com/user/rebuilt", "1.0.0")
      outcome.status.should eq("building")
      outcome.finished_at.should be_nil
      outcome.failed_at.should be_nil
      outcome.last_error.should be_nil
    end
  end

  # The reason the two statements are one transaction. Written separately, a
  # failure between them left crystaldocs holding a request row that said
  # 'succeeded' beside a version row that still said 'pending', and nothing
  # anywhere reconciles that afterwards.
  #
  # The second write is failed at the database with a CHECK constraint, not by a
  # stub, because the claim being tested is that Postgres rolling back the
  # second statement takes the first one with it.
  describe "when the version write fails" do
    it "leaves neither row written and reports the outcome as unrecorded" do
      DocsRows.register("github.com/user/atomic", "1.0.0")
      DocsRows.request("github.com/user/atomic", "1.0.0")

      DocsRows.refusing_doc_version_writes do
        expect_raises(CrystalShards::DocsBuildStatus::Unrecorded, /succeeded outcome of github.com\/user\/atomic@1.0.0/) do
          CrystalShards::DocsBuildStatus.new("github.com/user/atomic", "1.0.0").succeeded
        end
      end

      # Without the transaction this row reads 'succeeded': its UPDATE ran, was
      # accepted, and was never undone.
      DocsRows.request_status("github.com/user/atomic", "1.0.0").should eq("pending")
      DocsRows.version_status("github.com/user/atomic", "1.0.0").should eq("pending")
    end

    it "reports a lost failure as unrecorded too" do
      DocsRows.register("github.com/user/atomic-failure", "1.0.0")
      DocsRows.request("github.com/user/atomic-failure", "1.0.0")

      DocsRows.refusing_doc_version_writes do
        expect_raises(CrystalShards::DocsBuildStatus::Unrecorded, /failed outcome/) do
          CrystalShards::DocsBuildStatus.new("github.com/user/atomic-failure", "1.0.0")
            .failed("the shard does not compile")
        end
      end

      outcome = DocsRows.request_outcome("github.com/user/atomic-failure", "1.0.0")
      outcome.status.should eq("pending")
      outcome.last_error.should be_nil
    end

    # The one state allowed to go unrecorded: nothing durable is lost, because
    # both columns already read what the reader is already being shown and the
    # outcome that follows overwrites them from scratch.
    it "does not raise for the interim building state" do
      DocsRows.register("github.com/user/interim", "1.0.0")
      DocsRows.request("github.com/user/interim", "1.0.0")

      DocsRows.refusing_doc_version_writes do
        CrystalShards::DocsBuildStatus.new("github.com/user/interim", "1.0.0").building
      end

      DocsRows.request_status("github.com/user/interim", "1.0.0").should eq("pending")
      DocsRows.version_status("github.com/user/interim", "1.0.0").should eq("pending")
    end

    # A lost outcome leaves the connection usable. The transaction is rolled
    # back rather than left open, so the redelivery that repairs the outcome can
    # write on the very next call.
    it "leaves the connection able to record the retry" do
      DocsRows.register("github.com/user/recovered", "1.0.0")
      DocsRows.request("github.com/user/recovered", "1.0.0")
      status = CrystalShards::DocsBuildStatus.new("github.com/user/recovered", "1.0.0")

      DocsRows.refusing_doc_version_writes do
        expect_raises(CrystalShards::DocsBuildStatus::Unrecorded) { status.succeeded }
      end

      status.succeeded

      DocsRows.request_status("github.com/user/recovered", "1.0.0").should eq("succeeded")
      DocsRows.version_status("github.com/user/recovered", "1.0.0").should eq("success")
    end
  end
end
