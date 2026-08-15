require "../spec_helper"

private def reload(shard : Shard) : Shard
  ShardQuery.new.id(shard.id).first
end

# Every example installs its own indexer fake and restores the real seams in
# an `ensure`, the same discipline IndexShardWorker.dispatcher and
# IndexSweep.indexer already require of their own specs.
private def with_indexer(fake : Proc(Shard, ShardIndexer::Result), &)
  original_indexer = ShardIndexRequests.indexer
  original_timeout = ShardIndexRequests.inline_timeout
  ShardIndexRequests.indexer = fake

  yield
ensure
  ShardIndexRequests.indexer = original_indexer
  ShardIndexRequests.inline_timeout = original_timeout
end

# A fake indexer that succeeds immediately, writing indexed_at and a version
# the way the real ShardIndexer would, without reaching a host. `calls`
# counts invocations with Atomic rather than a plain Int32: several examples
# call this from more than one fiber at once, and a plain counter's
# read-modify-write can lose an increment under exactly that concurrency.
private def succeeding_indexer(calls : Atomic(Int32)? = nil) : Proc(Shard, ShardIndexer::Result)
  ->(shard : Shard) {
    calls.try(&.add(1))
    SaveShard.update!(shard, indexed_at: Time.utc, latest_version: "1.0.0", index_error: nil)
    ShardIndexer::Result.new(ShardIndexer::Outcome::Indexed, shard, versions: 1, indexed_version: "1.0.0")
  }
end

# A fake indexer that fails the way a real one does on an unreachable host:
# it stamps index_error and leaves indexed_at nil, mirroring
# ShardIndexer#finish.
private def failing_indexer(calls : Atomic(Int32)? = nil) : Proc(Shard, ShardIndexer::Result)
  ->(shard : Shard) {
    calls.try(&.add(1))
    SaveShard.update!(shard, index_error: "the repository could not be read")
    ShardIndexer::Result.new(ShardIndexer::Outcome::Failed, shard, detail: "the repository could not be read")
  }
end

# A fake indexer that never reports back inside the example's shrunk
# inline_timeout, standing in for a host that never answers.
private def hanging_indexer(calls : Atomic(Int32)? = nil) : Proc(Shard, ShardIndexer::Result)
  ->(shard : Shard) {
    calls.try(&.add(1))
    sleep 1.second
    ShardIndexer::Result.new(ShardIndexer::Outcome::Indexed, shard)
  }
end

# Indexing is built on first visit: this service is the thing standing
# between a cold shard page and IndexSweep's six-hourly pass. Every example
# is about how many times the indexer actually runs and what the row looks
# like afterward, because those are the properties that make a crawler
# harmless: too many runs and a stranger with a URL bar spends the host's
# rate limit, too few and a visited shard never gains content faster than
# the sweep would have given it anyway.
describe ShardIndexRequests do
  describe "a shard nobody has visited" do
    it "claims it, indexes it inline, and returns the shard with content" do
      with_indexer(succeeding_indexer) do
        shard = ShardFactory.create &.name("kemal").at("github.com", "kemalcr", "kemal")

        result = ShardIndexRequests.request(shard)

        result.should_not be_nil
        result.not_nil!.indexed_at.should_not be_nil
        result.not_nil!.latest_version.should eq("1.0.0")
      end
    end

    it "preloads shard_versions on the returned shard, matching every render_show_page caller" do
      with_indexer(succeeding_indexer) do
        shard = ShardFactory.create &.name("kemal").at("github.com", "kemalcr", "kemal")

        result = ShardIndexRequests.request(shard).not_nil!

        # Raises rather than lazily loading if this association was not
        # preloaded, so this line is the assertion.
        result.shard_versions.should be_a(Array(ShardVersion))
      end
    end

    it "stamps index_attempted_at before the render can see it" do
      with_indexer(succeeding_indexer) do
        shard = ShardFactory.create &.name("kemal").at("github.com", "kemalcr", "kemal")

        ShardIndexRequests.request(shard)

        reload(shard).index_attempted_at.should_not be_nil
      end
    end
  end

  describe "repeated visits" do
    it "indexes exactly once however many times the shard is visited" do
      calls = Atomic(Int32).new(0)

      with_indexer(succeeding_indexer(calls)) do
        shard = ShardFactory.create &.name("kemal").at("github.com", "kemalcr", "kemal")

        result = ShardIndexRequests.request(shard)
        4.times { ShardIndexRequests.request(reload(shard)) }

        result.should_not be_nil
        calls.get.should eq(1)
      end
    end

    # The reason the claim is a conditional UPDATE rather than a read
    # followed by a write. Several readers landing on the same cold shard at
    # once is the ordinary way a popular unindexed shard gets discovered, and
    # a check-then-write loses exactly there. A losing request must not wait
    # on the winner either, so the fake indexer blocks on `release` until the
    # test has already observed every loser return.
    it "indexes exactly once when the visits are concurrent, and a losing request does not wait on the winner" do
      calls = Atomic(Int32).new(0)
      release = Channel(Nil).new
      results = Channel(Shard?).new(8)

      slow_indexer = ->(shard : Shard) {
        calls.add(1)
        release.receive
        SaveShard.update!(shard, indexed_at: Time.utc)
        ShardIndexer::Result.new(ShardIndexer::Outcome::Indexed, shard)
      }

      with_indexer(slow_indexer) do
        shard = ShardFactory.create &.name("kemal").at("github.com", "kemalcr", "kemal")
        callers = 8

        callers.times do
          spawn do
            results.send(ShardIndexRequests.request(reload(shard)))
          end
        end

        # Every loser has to have already claimed-and-lost before the winner
        # is allowed to finish, which is what proves losers do not wait: they
        # can only have reached `results.send` this fast by returning nil
        # immediately rather than blocking on the fiber above.
        losers = (callers - 1).times.map { results.receive }.to_a
        losers.all?(&.nil?).should be_true

        release.send(nil)
        winner = results.receive

        winner.should_not be_nil
        calls.get.should eq(1)
      end
    end
  end

  describe "a shard that is already indexed" do
    it "does not index and returns nil" do
      calls = Atomic(Int32).new(0)

      with_indexer(succeeding_indexer(calls)) do
        shard = ShardFactory.create &.name("kemal")
          .at("github.com", "kemalcr", "kemal")
          .indexed_at(Time.utc)

        result = ShardIndexRequests.request(shard)

        result.should be_nil
        calls.get.should eq(0)
      end
    end
  end

  describe "a shard whose index is already in flight" do
    it "does not index while the claim is fresh" do
      calls = Atomic(Int32).new(0)

      with_indexer(succeeding_indexer(calls)) do
        shard = ShardFactory.create &.name("kemal")
          .at("github.com", "kemalcr", "kemal")
          .index_attempted_at(1.minute.ago)

        result = ShardIndexRequests.request(shard)

        result.should be_nil
        calls.get.should eq(0)
      end
    end
  end

  # Without a floor, every visitor to a shard that cannot be indexed re-claims
  # it, and one permanently broken repository with a trickle of traffic
  # starves the on-demand path for shards that would succeed.
  describe "the retry floor" do
    it "does not retry a failure that just happened" do
      calls = Atomic(Int32).new(0)

      with_indexer(failing_indexer(calls)) do
        shard = ShardFactory.create &.name("kemal")
          .at("github.com", "kemalcr", "kemal")
          .index_attempted_at(1.minute.ago)
          .index_error("timed out")

        result = ShardIndexRequests.request(shard)

        result.should be_nil
        calls.get.should eq(0)
      end
    end

    it "retries once the floor has passed" do
      calls = Atomic(Int32).new(0)

      with_indexer(succeeding_indexer(calls)) do
        shard = ShardFactory.create &.name("kemal")
          .at("github.com", "kemalcr", "kemal")
          .index_attempted_at(ShardIndexRequests::RETRY_FLOOR.ago - 1.minute)
          .index_error("timed out")

        result = ShardIndexRequests.request(shard)

        result.should_not be_nil
        calls.get.should eq(1)
      end
    end
  end

  describe "a shard with no identity" do
    it "does not index, because there is no host to fetch from and no key to key the claim on" do
      calls = Atomic(Int32).new(0)

      with_indexer(succeeding_indexer(calls)) do
        shard = insert_unidentified_shard("mystery", "not-a-url")

        result = ShardIndexRequests.request(shard)

        result.should be_nil
        calls.get.should eq(0)
      end
    end
  end

  describe "a host that fails to answer" do
    it "renders as unindexed rather than raising, and leaves the row reclaimable after the floor" do
      with_indexer(failing_indexer) do
        shard = ShardFactory.create &.name("kemal").at("github.com", "kemalcr", "kemal")

        result = ShardIndexRequests.request(shard)

        result.should be_nil
        row = reload(shard)
        row.indexed_at.should be_nil
        row.index_attempted_at.should_not be_nil
      end
    end
  end

  # ShardIndexer makes a handful of sequential host calls and none of it is
  # the minutes a documentation compile takes, so a reader's page load must
  # not be held hostage to a host that never answers at all.
  describe "a host that never answers" do
    it "gives up after inline_timeout, renders as unindexed, and leaves the row reclaimable after the floor" do
      calls = Atomic(Int32).new(0)

      with_indexer(hanging_indexer(calls)) do
        ShardIndexRequests.inline_timeout = 10.milliseconds
        shard = ShardFactory.create &.name("kemal").at("github.com", "kemalcr", "kemal")

        result = ShardIndexRequests.request(shard)

        result.should be_nil
        calls.get.should eq(1) # proves the indexer really was invoked, not skipped
        row = reload(shard)
        row.indexed_at.should be_nil
        row.index_attempted_at.should_not be_nil
      end
    end
  end

  describe "different shards" do
    it "are claimed and indexed independently" do
      calls = Atomic(Int32).new(0)

      with_indexer(succeeding_indexer(calls)) do
        kemal = ShardFactory.create &.name("kemal").at("github.com", "kemalcr", "kemal")
        radix = ShardFactory.create &.name("radix").at("github.com", "luislavena", "radix")

        ShardIndexRequests.request(kemal).should_not be_nil
        ShardIndexRequests.request(radix).should_not be_nil

        calls.get.should eq(2)
      end
    end
  end
end

# terraform/modules/services/locals.tf wires GITHUB_TOKEN into the
# crystalshards service env, the exact name Discovery::Credentials::TOKEN_ENV
# uses for the discover-shards Job (the "DISCOVERY_GITHUB_TOKEN" name in this
# file's own comment is not what either the Job or this service actually get
# set; both fall through to GITHUB_TOKEN). This spec is what stops a future
# edit from quietly renaming the env var this service reads without also
# renaming what terraform provides, which would drop indexing back to
# anonymous with no error anywhere.
describe GithubRepositoryApi do
  describe ".token_from_env" do
    it "reads GITHUB_TOKEN, the name terraform actually wires for both the web service and the Job" do
      with_env("DISCOVERY_GITHUB_TOKEN", nil) do
        with_env("GITHUB_TOKEN", "the-shared-discovery-token") do
          GithubRepositoryApi.token_from_env.should eq("the-shared-discovery-token")
        end
      end
    end

    it "returns nil, not raise, when neither is set, so an unconfigured host falls through to anonymous rather than crashing the render" do
      with_env("DISCOVERY_GITHUB_TOKEN", nil) do
        with_env("GITHUB_TOKEN", nil) do
          GithubRepositoryApi.token_from_env.should be_nil
        end
      end
    end
  end
end
