require "../spec_helper"

# The one-off that repairs the catalogue the writer cannot reach: every version
# built before the builder was taught to write build_status still says
# 'pending', so DependencyIndex, which selects the versions whose build_status
# is 'success', sees an empty set and no cross-package documentation link works.
#
# The evidence it is allowed to use is an object in the bucket. Everything here
# is about what happens when that object is there and when it is not.
describe CrystalShards::DocsStatusReconciliation do
  it "marks a pending version whose artifact is in the bucket" do
    DocsRows.register("github.com/user/built", "1.0.0")
    store = FakeObjectStore.new(["github.com/user/built/1.0.0/docs.json"])

    report = CrystalShards::DocsStatusReconciliation.run(store)

    DocsRows.version_status("github.com/user/built", "1.0.0").should eq("success")
    report.marked.map(&.to_s).should eq(["github.com/user/built@1.0.0"])
    report.unbuilt.should eq(0)
  end

  # The one that must not be guessed at. An absent artifact is a version nobody
  # has built, which is exactly what pending means, so the row is left as it is
  # rather than being marked success or rewritten to failed.
  it "leaves a pending version whose artifact is absent" do
    DocsRows.register("github.com/user/unbuilt", "1.0.0")
    store = FakeObjectStore.new

    report = CrystalShards::DocsStatusReconciliation.run(store)

    DocsRows.version_status("github.com/user/unbuilt", "1.0.0").should eq("pending")
    report.marked.should be_empty
    report.unbuilt.should eq(1)
  end

  it "decides each version of a package separately" do
    DocsRows.register("github.com/user/mixed", "1.0.0")
    DocsRows.register("github.com/user/mixed", "2.0.0")
    store = FakeObjectStore.new(["github.com/user/mixed/2.0.0/docs.json"])

    report = CrystalShards::DocsStatusReconciliation.run(store)

    DocsRows.version_status("github.com/user/mixed", "1.0.0").should eq("pending")
    DocsRows.version_status("github.com/user/mixed", "2.0.0").should eq("success")
    report.marked.map(&.to_s).should eq(["github.com/user/mixed@2.0.0"])
    report.unbuilt.should eq(1)
  end

  # storage_path is written at registration and names where the artifact would
  # go, present or not, so it cannot be the evidence. A row whose prefix holds
  # other objects but no docs.json has no documentation to link to.
  it "does not accept anything but the artifact itself" do
    DocsRows.register("github.com/user/scratch", "1.0.0")
    store = FakeObjectStore.new([
      "github.com/user/scratch/1.0.0/README.md",
      "build-scratch/github.com/user/scratch/1.0.0/docs.json",
    ])

    CrystalShards::DocsStatusReconciliation.run(store)

    DocsRows.version_status("github.com/user/scratch", "1.0.0").should eq("pending")
  end

  it "leaves states something wrote deliberately alone" do
    DocsRows.register("github.com/user/failed-build", "1.0.0", build_status: "failed")
    DocsRows.register("github.com/user/in-flight", "1.0.0", build_status: "building")
    DocsRows.register("github.com/user/already", "1.0.0", build_status: "success")
    store = FakeObjectStore.new([
      "github.com/user/failed-build/1.0.0/docs.json",
      "github.com/user/in-flight/1.0.0/docs.json",
      "github.com/user/already/1.0.0/docs.json",
    ])

    report = CrystalShards::DocsStatusReconciliation.run(store)

    DocsRows.version_status("github.com/user/failed-build", "1.0.0").should eq("failed")
    DocsRows.version_status("github.com/user/in-flight", "1.0.0").should eq("building")
    DocsRows.version_status("github.com/user/already", "1.0.0").should eq("success")
    report.examined.should eq(0)
  end

  # A request row exists only where a reader asked for a build from a page, and
  # an artifact in a bucket says nothing about a request nobody made.
  it "does not touch the build request" do
    DocsRows.register("github.com/user/requested", "1.0.0")
    DocsRows.request("github.com/user/requested", "1.0.0")
    store = FakeObjectStore.new(["github.com/user/requested/1.0.0/docs.json"])

    CrystalShards::DocsStatusReconciliation.run(store)

    DocsRows.request_status("github.com/user/requested", "1.0.0").should eq("pending")
    DocsRows.version_status("github.com/user/requested", "1.0.0").should eq("success")
  end

  it "finds nothing left to do on a second run" do
    DocsRows.register("github.com/user/twice", "1.0.0")
    store = FakeObjectStore.new(["github.com/user/twice/1.0.0/docs.json"])

    CrystalShards::DocsStatusReconciliation.run(store)
    second = CrystalShards::DocsStatusReconciliation.run(store)

    second.marked.should be_empty
    second.examined.should eq(0)
    DocsRows.version_status("github.com/user/twice", "1.0.0").should eq("success")
  end

  # "the bucket is empty" and "we never saw the bucket" both arrive as nothing
  # marked, and the second one must not look like a clean run. The listing
  # happens before any row is read, so a store that cannot answer stops the run
  # before it writes.
  it "changes nothing and raises when the store cannot answer" do
    DocsRows.register("github.com/user/unknown-storage", "1.0.0")
    store = FakeObjectStore.new(["github.com/user/unknown-storage/1.0.0/docs.json"], unavailable: true)

    expect_raises(CrystalStorage::Unavailable) do
      CrystalShards::DocsStatusReconciliation.run(store)
    end

    DocsRows.version_status("github.com/user/unknown-storage", "1.0.0").should eq("pending")
  end

  it "counts the artifacts it decided from" do
    DocsRows.register("github.com/user/counted", "1.0.0")
    store = FakeObjectStore.new([
      "github.com/user/counted/1.0.0/docs.json",
      "github.com/user/elsewhere/3.0.0/docs.json",
    ])

    report = CrystalShards::DocsStatusReconciliation.run(store)

    report.artifacts.should eq(2)
    report.marked.size.should eq(1)
  end

  describe ".render" do
    it "reports what was left pending and why" do
      DocsRows.register("github.com/user/rendered", "1.0.0")
      DocsRows.register("github.com/user/absent", "1.0.0")
      store = FakeObjectStore.new(["github.com/user/rendered/1.0.0/docs.json"])

      report = CrystalShards::DocsStatusReconciliation.run(store)
      output = String.build { |io| CrystalShards::DocsStatusReconciliation.render(report, io) }

      output.should contain("marked 1 of 2 pending versions as built")
      output.should contain("1 with no artifact")
      output.should contain("github.com/user/rendered@1.0.0")
      output.should_not contain("github.com/user/absent@1.0.0")
    end

    it "says so when there is nothing pending" do
      report = CrystalShards::DocsStatusReconciliation.run(FakeObjectStore.new)
      output = String.build { |io| CrystalShards::DocsStatusReconciliation.render(report, io) }

      output.should contain("Nothing was pending")
    end
  end
end
