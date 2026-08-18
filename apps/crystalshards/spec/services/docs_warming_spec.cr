require "../spec_helper"

# Warming the head of the catalogue so its first reader is not the one who pays
# for the build.
#
# Runs against the real docs database, like docs_build_status_spec, because the
# whole question this service asks is "does crystaldocs already have this", and
# a fake cannot answer it the way the join does.
private def warm(scan : Int32 = 100, enqueue : Int32 = 25, index : Int32 = 0)
  CrystalShards::DocsWarming.run(
    CrystalShards::DocsWarming::Options.new(scan: scan, enqueue: enqueue, index: index)
  )
end

# Stands in for a real index pass. The sweep's own seam, so nothing here
# reaches a git host.
private def with_indexer(outcome : ShardIndexer::Outcome, read : Array(String), &)
  # The original is read before the `begin`, deliberately. A local assigned
  # inside a body that has an `ensure` is nilable as far as the compiler is
  # concerned, because the raise could have happened before the assignment,
  # and restoring a nil would leave the sweep with no indexer for the rest of
  # the suite.
  original = IndexSweep.indexer

  begin
    IndexSweep.indexer = ->(shard : Shard) do
      read << (shard.canonical_slug || shard.name)
      SaveShard.update!(shard, indexed_at: Time.utc) if outcome.indexed?
      ShardIndexer::Result.new(outcome, shard, detail: outcome.indexed? ? nil : "the host refused")
    end

    yield
  ensure
    IndexSweep.indexer = original
  end
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

  describe "when the queue refuses" do
    # The first live run of this Job printed nineteen packages under
    # "Commissioned:", raised on every one of them, and exited 0. A warmer that
    # reports success while queueing nothing is worse than one that does
    # nothing at all: the missing documentation is the only remaining symptom,
    # and the Job an operator would check is green.
    it "counts a refused enqueue as a failure and fails the run" do
      RefusingJobQueue.install
      shard_with("github.com/acme/refused", "1.0.0", stars: 500)

      report = warm

      report.enqueued.should be_empty
      report.failures.map(&.candidate.package_name).should eq(["github.com/acme/refused"])
      report.exit_code.should eq(1)
    end

    it "says plainly that an identical reason everywhere is configuration" do
      RefusingJobQueue.install
      2.times { |i| shard_with("github.com/acme/ref#{i}", "1.0.0", stars: 100 - i) }

      report = warm
      rendered = String.build { |io| CrystalShards::DocsWarming.render(report, io) }

      rendered.should contain("Refused by the queue:")
      rendered.should contain("misconfigured Job, not a bad shard")
      rendered.should_not contain("Exit 0.")
    end
  end

  describe "reading popular shards nobody has read" do
    it "indexes an unread popular shard before trying to document it" do
      # The ordering that makes the rest of the Job reach a popular shard at
      # all. An unindexed shard has no versions, so the documentation pass
      # counts it as having no published version and skips it, on every run,
      # forever.
      shard = ShardFactory.create &.name("unread")
        .repository_url("https://github.com/acme/unread")
        .canonical_slug("github.com/acme/unread")
        .github_stars(900)

      read = [] of String

      with_indexer(ShardIndexer::Outcome::Indexed, read) do
        report = warm(index: 5)

        read.should eq(["github.com/acme/unread"])
        report.indexed.should eq(["github.com/acme/unread"])
      end
    end

    it "leaves a shard the registry has already read alone" do
      # Re-reading what the registry knows is IndexSweep's job, and it walks
      # the whole catalogue on a fairness cursor. A second opinion about
      # staleness here would have the two fighting over one rate limit.
      shard_with("github.com/acme/known", "1.0.0", stars: 900)
      SaveShard.update!(ShardQuery.new.canonical_slug("github.com/acme/known").first, indexed_at: Time.utc)

      read = [] of String

      with_indexer(ShardIndexer::Outcome::Indexed, read) do
        report = warm(index: 5)

        # Scoped to this shard rather than asserting nothing at all was read:
        # ShardVersionFactory creates its own shard when it is not given one,
        # so the table holds an unrelated unindexed row that this pass is
        # entitled to pick up.
        read.should_not contain("github.com/acme/known")
        report.indexed.should_not contain("github.com/acme/known")
      end
    end

    it "records a shard it could not read instead of losing it" do
      ShardFactory.create &.name("refuses")
        .repository_url("https://github.com/acme/refuses")
        .canonical_slug("github.com/acme/refuses")
        .github_stars(900)

      read = [] of String

      with_indexer(ShardIndexer::Outcome::Failed, read) do
        report = warm(index: 5)

        report.indexed.should be_empty
        report.index_failures.first.should contain("github.com/acme/refuses")
      end
    end

    it "reads no more shards than it was allowed" do
      3.times do |i|
        ShardFactory.create &.name("cold#{i}")
          .repository_url("https://github.com/acme/cold#{i}")
          .canonical_slug("github.com/acme/cold#{i}")
          .github_stars(900 - i)
      end

      read = [] of String

      with_indexer(ShardIndexer::Outcome::Indexed, read) do
        warm(index: 2)

        read.size.should eq(2)
      end
    end
  end
end
