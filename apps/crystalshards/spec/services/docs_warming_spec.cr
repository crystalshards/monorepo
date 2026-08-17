require "../spec_helper"

# Warming the head of the catalogue so its first reader is not the one who pays
# for the build.
#
# Runs against the real docs database, like docs_build_status_spec, because the
# whole question this service asks is "does crystaldocs already have this", and
# a fake cannot answer it the way the join does.
private def warm(scan : Int32 = 100, enqueue : Int32 = 25)
  CrystalShards::DocsWarming.run(
    CrystalShards::DocsWarming::Options.new(scan: scan, enqueue: enqueue)
  )
end

# A shard with one published version, ranked by nothing in particular. The
# ordering examples set stars explicitly; the rest only need a row.
private def shard_with(slug : String, version : String, stars : Int32? = nil)
  shard = ShardFactory.create &.name(slug.split('/').last)
    .repository_url("https://#{slug}")
    .canonical_slug(slug)
    .github_stars(stars)

  ShardVersionFactory.create &.shard_id(shard.id).version(version)
  shard
end

describe CrystalShards::DocsWarming do
  describe "selection" do
    it "commissions a build for a popular shard nobody has documented" do
      queue = RecordingJobQueue.install
      shard_with("github.com/acme/hot", "1.2.0", stars: 500)

      report = warm

      queue.dispatched.map { |d| {d.job, d.shard_name, d.version} }
        .should eq([{:build_docs, "github.com/acme/hot", "1.2.0"}])
      report.enqueued.size.should eq(1)
    end

    it "skips a version this site has already built" do
      queue = RecordingJobQueue.install
      shard_with("github.com/acme/done", "1.0.0", stars: 500)
      DocsRows.register("github.com/acme/done", "1.0.0")
      CrystalShards::DocsBuildStatus.new("github.com/acme/done", "1.0.0").succeeded

      report = warm

      queue.count_for(:build_docs).should eq(0)
      report.already_documented.should eq(1)
    end

    it "skips a version already on the queue, so a reader's own request is not duplicated" do
      # A pending row usually means somebody asked for this a moment ago.
      # Commissioning it again spends a second clone and compile to produce a
      # byte-identical artifact.
      queue = RecordingJobQueue.install
      shard_with("github.com/acme/queued", "1.0.0", stars: 500)
      DocsRows.register("github.com/acme/queued", "1.0.0")
      DocsRows.request("github.com/acme/queued", "1.0.0")

      report = warm

      queue.count_for(:build_docs).should eq(0)
      report.in_flight.should eq(1)
    end

    it "retries a version whose last build failed" do
      # Deliberately NOT skipped. crystaldocs owns the retry floor and applies
      # it when a reader asks; a warmer that excluded every past failure would
      # never rebuild a shard that failed once on a transient network error.
      queue = RecordingJobQueue.install
      shard_with("github.com/acme/flaky", "1.0.0", stars: 500)
      DocsRows.register("github.com/acme/flaky", "1.0.0")
      DocsRows.request("github.com/acme/flaky", "1.0.0")
      CrystalShards::DocsBuildStatus.new("github.com/acme/flaky", "1.0.0").failed("network reset")

      warm

      queue.count_for(:build_docs).should eq(1)
    end

    it "counts a shard with no published version instead of failing on it" do
      queue = RecordingJobQueue.install
      ShardFactory.create &.name("tagless")
        .repository_url("https://github.com/acme/tagless")
        .canonical_slug("github.com/acme/tagless")

      report = warm

      queue.count_for(:build_docs).should eq(0)
      report.no_version.should eq(1)
    end

    it "asks for the newest version, not whichever row came back first" do
      shard = ShardFactory.create &.name("many")
        .repository_url("https://github.com/acme/many")
        .canonical_slug("github.com/acme/many")

      # 1.10.0 is the newest. A string sort would pick 1.9.0.
      ["1.9.0", "1.10.0", "1.2.0"].each do |version|
        ShardVersionFactory.create &.shard_id(shard.id).version(version)
      end

      queue = RecordingJobQueue.install
      warm

      queue.dispatched.map(&.version).should eq(["1.10.0"])
    end
  end

  describe "bounds" do
    it "commissions no more builds than it was allowed" do
      # The expensive number. Every build is a clone and a compile on a fleet
      # shared with the builds readers are waiting on right now.
      queue = RecordingJobQueue.install
      5.times { |i| shard_with("github.com/acme/pkg#{i}", "1.0.0", stars: 100 - i) }

      report = warm(enqueue: 2)

      queue.count_for(:build_docs).should eq(2)
      report.enqueued.size.should eq(2)
    end

    it "refuses a bound that is not a positive number" do
      ENV["WARM_MAX_BUILDS"] = "0"

      expect_raises(CrystalShards::DocsWarming::ConfigurationError, /positive whole number/) do
        CrystalShards::DocsWarming::Options.from_env
      end
    ensure
      ENV.delete("WARM_MAX_BUILDS")
    end

    it "falls back to its defaults when nothing is set" do
      options = CrystalShards::DocsWarming::Options.from_env

      options.scan.should eq(CrystalShards::DocsWarming::DEFAULT_SCAN)
      options.enqueue.should eq(CrystalShards::DocsWarming::DEFAULT_ENQUEUE)
    end
  end
end
