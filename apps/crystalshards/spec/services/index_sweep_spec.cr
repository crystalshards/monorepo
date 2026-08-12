require "../spec_helper"

# Required directly, like the discovery specs: src/app.cr carries only
# version_order out of services/, because the sweep exists for a Cloud Run Job
# that never boots Lucky and has no business in the web server binary.
require "../../src/services/index_sweep"

# One bounded pass of indexing, and the exit code a Cloud Run Job hands back.
#
# Nothing here touches a host. The per-shard work goes through IndexSweep.indexer,
# so these exercise what the sweep itself decides: which shards are due and in
# what order, how many it takes, what it does with each outcome, and what an
# operator reads out the other end. The one spec that runs the real indexer
# installs RecordedGithub, which restores the previous source builder in an
# `ensure`.
private def default_indexer : Proc(Shard, ShardIndexer::Result)
  ->(shard : Shard) { ShardIndexer.index(shard) }
end

# Replaces the per-shard indexer with `answer` and records every shard it was
# handed, so a spec can assert the order a run walked as well as its totals.
private def with_indexer(
  answer : Proc(Shard, ShardIndexer::Result),
  indexed : Array(String) = [] of String,
  &
)
  IndexSweep.indexer = ->(shard : Shard) do
    indexed << (shard.canonical_slug || shard.name)
    answer.call(shard)
  end

  begin
    yield
  ensure
    IndexSweep.indexer = default_indexer
  end
end

private def succeeding(versions : Int32 = 1) : Proc(Shard, ShardIndexer::Result)
  ->(shard : Shard) do
    ShardIndexer::Result.new(ShardIndexer::Outcome::Indexed, shard, versions: versions)
  end
end

private def failing(detail : String = "502 from the host") : Proc(Shard, ShardIndexer::Result)
  ->(shard : Shard) do
    ShardIndexer::Result.new(ShardIndexer::Outcome::Failed, shard, detail: detail)
  end
end

private def options(max_shards : Int32 = 300, min_age : Time::Span = 20.hours) : IndexSweep::Options
  IndexSweep::Options.new(max_shards: max_shards, min_age: min_age)
end

private def rendered(report : IndexSweep::Report) : String
  String.build { |io| IndexSweep.render(report, io) }
end

# A shard placed at a known point in the queue. `attempted` nil is a shard that
# has never been indexed, which is the whole reason nulls sort first.
private def queued(slug : String, attempted : Time? = nil) : Shard
  owner, _, repo = slug.partition("/")
  shard = ShardFactory.create &.name(repo).at("github.com", owner, repo)
  return shard unless attempted

  operation = SaveShard.new(shard)
  operation.index_attempted_at.value = attempted
  operation.update!
end

describe IndexSweep do
  describe "which shards are due" do
    it "returns the never-indexed ones first" do
      # Their pages are empty, so they are the whole point of a run. A shard
      # indexed an hour ago is worth less than one indexed never.
      recent = queued("acme/recent", attempted: Time.utc - 1.hour)
      stale = queued("acme/stale", attempted: Time.utc - 40.hours)
      fresh = queued("acme/never")

      due = IndexSweep.due(options)

      due.map(&.canonical_slug).should eq([
        fresh.canonical_slug,
        stale.canonical_slug,
      ])
      due.map(&.canonical_slug).should_not contain(recent.canonical_slug)
    end

    it "orders the stalest first among shards that have been indexed" do
      oldest = queued("acme/oldest", attempted: Time.utc - 90.hours)
      middle = queued("acme/middle", attempted: Time.utc - 60.hours)
      newest = queued("acme/newest", attempted: Time.utc - 30.hours)

      IndexSweep.due(options).map(&.canonical_slug).should eq([
        oldest.canonical_slug,
        middle.canonical_slug,
        newest.canonical_slug,
      ])
    end

    it "breaks ties by id, so the order is total" do
      # Without it the rows that all have a null cursor come back in whatever
      # order Postgres feels like, and two consecutive runs could pick
      # overlapping sets and never reach the tail.
      first = queued("acme/one")
      second = queued("acme/two")
      third = queued("acme/three")

      ids = IndexSweep.due(options).map(&.id)
      ids.should eq([first.id, second.id, third.id])
      ids.should eq(ids.sort)
      # Stated twice on purpose: the property is that repeating the query
      # repeats the answer.
      IndexSweep.due(options).map(&.id).should eq(ids)
    end

    it "leaves out a shard indexed inside the minimum age" do
      # Reindexing sooner spends requests to learn a star count moved by three.
      queued("acme/justdone", attempted: Time.utc - 1.hour)

      IndexSweep.due(options).should be_empty
    end

    it "ignores the minimum age for a shard that has never been indexed" do
      never = queued("acme/never")

      IndexSweep.due(options(min_age: 500.hours)).map(&.canonical_slug)
        .should eq([never.canonical_slug])
    end

    it "bounds a run to max_shards, taking the stalest of them" do
      oldest = queued("acme/oldest", attempted: Time.utc - 90.hours)
      middle = queued("acme/middle", attempted: Time.utc - 60.hours)
      queued("acme/newest", attempted: Time.utc - 30.hours)

      due = IndexSweep.due(options(max_shards: 2))

      due.size.should eq(2)
      due.map(&.canonical_slug).should eq([oldest.canonical_slug, middle.canonical_slug])
    end

    it "hands the run exactly the shards the bound allows, in that order" do
      queued("acme/oldest", attempted: Time.utc - 90.hours)
      queued("acme/middle", attempted: Time.utc - 60.hours)
      queued("acme/newest", attempted: Time.utc - 30.hours)

      indexed = [] of String
      with_indexer(succeeding, indexed) { IndexSweep.run(options(max_shards: 2)) }

      indexed.should eq(["github.com/acme/oldest", "github.com/acme/middle"])
    end
  end

  describe "the bound from the environment" do
    it "defaults when the variable is unset" do
      IndexSweep::Options.parse(nil).max_shards.should eq(IndexSweep::DEFAULT_MAX_SHARDS)
      IndexSweep::Options.parse("").max_shards.should eq(IndexSweep::DEFAULT_MAX_SHARDS)
      IndexSweep::Options.parse("   ").max_shards.should eq(IndexSweep::DEFAULT_MAX_SHARDS)
    end

    it "takes a positive whole number" do
      IndexSweep::Options.parse("25").max_shards.should eq(25)
      IndexSweep::Options.parse(" 25 ").max_shards.should eq(25)
    end

    it "refuses a typo rather than silently using the default" do
      # A typo becoming the default is how an operator ends up certain they
      # changed the budget and unable to see any effect.
      message = expect_raises(IndexSweep::ConfigurationError) do
        IndexSweep::Options.parse("thirty")
      end.message.not_nil!

      message.should contain("INDEX_MAX_SHARDS")
      message.should contain("positive whole number")
      message.should contain(%("thirty"))
    end

    it "refuses zero and negatives, which would index nothing forever" do
      expect_raises(IndexSweep::ConfigurationError) { IndexSweep::Options.parse("0") }
      expect_raises(IndexSweep::ConfigurationError) { IndexSweep::Options.parse("-5") }
      expect_raises(IndexSweep::ConfigurationError) { IndexSweep::Options.parse("12.5") }
    end
  end

  describe "the exit code" do
    it "fails a run in which everything failed" do
      # Every repository failing is a bad token or a host outage, and that must
      # not exit 0.
      queued("acme/one")
      queued("acme/two")

      report = with_indexer(failing) { IndexSweep.run(options) }

      report.attempted.should eq(2)
      report.failed.should eq(2)
      report.ok?.should be_false
      report.exit_code.should eq(1)
    end

    it "succeeds a run in which one of several failed" do
      # One repository being deleted or renamed mid-crawl is normal.
      queued("acme/good")
      queued("acme/bad")

      mixed = ->(shard : Shard) do
        if shard.repo == "bad"
          ShardIndexer::Result.new(ShardIndexer::Outcome::Failed, shard, detail: "gone")
        else
          ShardIndexer::Result.new(ShardIndexer::Outcome::Indexed, shard, versions: 3)
        end
      end

      report = with_indexer(mixed) { IndexSweep.run(options) }

      report.indexed.should eq(1)
      report.failed.should eq(1)
      report.versions.should eq(3)
      report.ok?.should be_true
      report.exit_code.should eq(0)
    end

    it "succeeds a run that had nothing to do" do
      report = with_indexer(succeeding) { IndexSweep.run(options) }

      report.attempted.should eq(0)
      report.ok?.should be_true
      report.exit_code.should eq(0)
      rendered(report).should contain("Nothing was due.")
    end

    it "does not fail a run on unsupported hosts alone" do
      # A host the indexer cannot read yet is not a fault. Counting it as a
      # failure would make every run red for a reason nobody can fix by fixing
      # anything.
      queued("acme/one")
      queued("acme/two")

      unsupported = ->(shard : Shard) do
        ShardIndexer::Result.new(
          ShardIndexer::Outcome::Unsupported,
          shard,
          detail: "sr.ht is not a host the registry can read",
        )
      end

      report = with_indexer(unsupported) { IndexSweep.run(options) }

      report.unsupported.should eq(2)
      report.failed.should eq(0)
      # Counted in attempted, so the arithmetic adds up: a sweep reporting
      # "attempted 300, indexed 40" with 260 unaccounted for is how a whole
      # host stays empty without anyone noticing.
      report.attempted.should eq(2)
      report.ok?.should be_true
      report.exit_code.should eq(0)
      rendered(report).should contain("unsupported host 2")
    end

    it "counts an unavailable repository without failing the run" do
      queued("acme/gone")

      vanished = ->(shard : Shard) do
        ShardIndexer::Result.new(ShardIndexer::Outcome::Unavailable, shard, detail: "404")
      end

      report = with_indexer(vanished) { IndexSweep.run(options) }

      report.unavailable.should eq(1)
      report.attempted.should eq(1)
      report.ok?.should be_true
      rendered(report).should contain("unavailable 1")
    end
  end

  describe "a shard that raises" do
    it "keeps sweeping the rest and records the raise as a failure" do
      # Letting the exception out loses every shard after it and, worse, loses
      # the printed summary of the ones already done.
      queued("acme/one")
      queued("acme/two")
      queued("acme/three")

      indexed = [] of String
      raising = ->(shard : Shard) do
        raise "connection reset" if shard.repo == "two"
        ShardIndexer::Result.new(ShardIndexer::Outcome::Indexed, shard, versions: 1)
      end

      report = with_indexer(raising, indexed) { IndexSweep.run(options) }

      indexed.size.should eq(3)
      report.indexed.should eq(2)
      report.failed.should eq(1)
      report.attempted.should eq(3)
      report.ok?.should be_true
      rendered(report).should contain("connection reset")
    end

    it "names a raise with no message by its class rather than blank" do
      queued("acme/one")

      # The proc type is declared rather than inferred, and it has to be.
      #
      # A proc literal whose body always raises infers Proc(Shard, NoReturn).
      # Passing that where Proc(Shard, ShardIndexer::Result) is expected and
      # then calling it through with_indexer's closure miscompiles on Linux
      # x86_64: the process dies with SIGSEGV inside print_backtrace, with no
      # usable stack. It passes on macOS arm64, which is how it reached CI.
      #
      # Bisected in a linux/amd64 container on the CI compiler: every raising
      # variant crashed while the proc type was inferred, and the same bodies
      # passed with the type declared or with one branch returning a Result.
      answer = Proc(Shard, ShardIndexer::Result).new { |_shard| raise IO::Error.new }

      report = with_indexer(answer) { IndexSweep.run(options) }

      report.failures.first.should contain("IO::Error")
    end
  end

  describe "what an operator reads" do
    it "caps the failure list rather than printing hundreds of lines" do
      30.times { |index| queued("acme/shard#{index}") }

      report = with_indexer(failing) { IndexSweep.run(options) }

      report.failed.should eq(30)
      report.failures.size.should eq(20)
    end

    it "names the shard and the reason on each failure line" do
      queued("acme/broken")

      report = with_indexer(failing("502 from the host")) { IndexSweep.run(options) }

      rendered(report).should contain("github.com/acme/broken: 502 from the host")
    end

    it "states the bound and the cursor, so a short run is not read as a stall" do
      queued("acme/one")

      report = with_indexer(succeeding) { IndexSweep.run(options(max_shards: 7)) }
      output = rendered(report)

      output.should contain("Bound: 7 shards this run, stalest first.")
      output.should contain("Cursor: shards.index_attempted_at")
      output.should contain("indexed 1, 1 version")
    end

    it "pluralises the version count" do
      queued("acme/one")

      report = with_indexer(succeeding(versions: 4)) { IndexSweep.run(options) }

      rendered(report).should contain("4 versions")
    end

    it "reports how much of the registry has content" do
      queued("acme/one")
      queued("acme/two")

      IndexSweep.coverage_summary.should contain("Indexed 0 of 2 shards (0.0%).")
      IndexSweep.coverage_summary.should contain("2 still have no content")
    end

    it "says the registry is empty rather than dividing by zero" do
      IndexSweep.coverage_summary
        .should eq("Registry is empty: discovery has found nothing to index.")
    end

    it "drops the follow-up sentence once everything has content" do
      shard = queued("acme/one")
      operation = SaveShard.new(shard)
      operation.indexed_at.value = Time.utc
      operation.update!

      summary = IndexSweep.coverage_summary
      summary.should contain("Indexed 1 of 1 shards (100.0%).")
      summary.should_not contain("still have no content")
    end
  end

  describe "a run driven end to end" do
    it "indexes a due shard through the real indexer and advances its cursor" do
      # The one spec that runs both halves together, so the seam a sweep uses
      # in production is the seam a spec proved. Still no network: the source
      # is a recording and an unscripted repo_path raises.
      shard = queued("kemalcr/kemal")
      github = RecordedGithub.new("kemalcr/kemal")
        .repository(stars: 3903, default_branch: "master")
        .tags("v1.6.0", "v1.5.0")
        .file("v1.6.0", "shard.yml", "name: kemal\ncrystal: \">= 1.12.0\"\n")
        .file("v1.6.0", "README.md", "# Kemal")

      report = RecordedGithub.install(github) { IndexSweep.run(options) }

      report.indexed.should eq(1)
      report.versions.should eq(2)
      report.exit_code.should eq(0)

      row = ShardQuery.new.id(shard.id).first
      row.github_stars.should eq(3903)
      row.latest_version.should eq("1.6.0")
      row.index_attempted_at.should_not be_nil
      row.indexed_at.should_not be_nil

      # A second run finds nothing due, which is what makes a pass strictly
      # advance rather than reindexing the same head forever.
      IndexSweep.due(options).should be_empty
    end
  end
end
