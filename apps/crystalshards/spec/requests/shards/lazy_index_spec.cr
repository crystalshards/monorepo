require "../../spec_helper"

private def with_indexer(fake : Proc(Shard, ShardIndexer::Result), &)
  original_indexer = ShardIndexRequests.indexer
  original_timeout = ShardIndexRequests.inline_timeout
  ShardIndexRequests.indexer = fake

  yield
ensure
  ShardIndexRequests.indexer = original_indexer
  ShardIndexRequests.inline_timeout = original_timeout
end

private def succeeding_indexer(calls : Atomic(Int32)? = nil) : Proc(Shard, ShardIndexer::Result)
  ->(shard : Shard) {
    calls.try(&.add(1))
    SaveShard.update!(shard, indexed_at: Time.utc, latest_version: "1.6.0")
    ShardVersionFactory.create &.shard_id(shard.id).version("1.6.0")
    ShardIndexer::Result.new(ShardIndexer::Outcome::Indexed, shard, versions: 1, indexed_version: "1.6.0")
  }
end

private def failing_indexer(calls : Atomic(Int32)? = nil) : Proc(Shard, ShardIndexer::Result)
  ->(shard : Shard) {
    calls.try(&.add(1))
    SaveShard.update!(shard, index_error: "the repository could not be read")
    ShardIndexer::Result.new(ShardIndexer::Outcome::Failed, shard, detail: "the repository could not be read")
  }
end

private def hanging_indexer(calls : Atomic(Int32)? = nil) : Proc(Shard, ShardIndexer::Result)
  ->(shard : Shard) {
    calls.try(&.add(1))
    sleep 1.second
    ShardIndexer::Result.new(ShardIndexer::Outcome::Indexed, shard)
  }
end

# Indexing is built the first time a shard is visited, so every one of the
# three show routes is a spend endpoint. The invariant, and the whole reason
# this is safe to expose: the claim is keyed on the shard's own identity and
# never on the requested path or the route that reached it, so a crawler
# walking invented paths under one cold shard still commissions the same one
# indexing pass.
describe "indexing a shard on first visit" do
  describe "a shard that has never been indexed" do
    it "indexes it inline and renders its versions on the very first visit" do
      with_indexer(succeeding_indexer) do
        shard = ShardFactory.create &.name("kemal").at("github.com", "kemalcr", "kemal")

        response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

        response.status_code.should eq(200)
        response.body.should contain("1.6.0")
        response.body.should_not contain("found but not read yet")
      end
    end
  end

  describe "a concurrent second visit" do
    it "does not index and renders the honest state, while the first visit still indexes" do
      calls = Atomic(Int32).new(0)
      release = Channel(Nil).new
      responses = Channel(HTTP::Client::Response).new(2)

      slow_indexer = ->(shard : Shard) {
        calls.add(1)
        release.receive
        SaveShard.update!(shard, indexed_at: Time.utc, latest_version: "1.6.0")
        ShardVersionFactory.create &.shard_id(shard.id).version("1.6.0")
        ShardIndexer::Result.new(ShardIndexer::Outcome::Indexed, shard, versions: 1, indexed_version: "1.6.0")
      }

      with_indexer(slow_indexer) do
        shard = ShardFactory.create &.name("kemal").at("github.com", "kemalcr", "kemal")

        spawn { responses.send(BrowserClient.exec(Shards::Show.with(**identity_of(shard)))) }

        # Waits for the first visit to have actually claimed and entered the
        # indexer before the second is sent, which is what makes the second
        # visit's claim attempt a genuine loss rather than a race that
        # happens to land first by luck.
        calls.get.should eq(0)
        until calls.get == 1
          Fiber.yield
        end

        second = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))
        second.status_code.should eq(200)
        second.body.should contain("found but not read yet")
        second.body.should contain("requested indexing")

        release.send(nil)
        first = responses.receive
        first.status_code.should eq(200)
        first.body.should contain("1.6.0")

        calls.get.should eq(1)
      end
    end
  end

  describe "a shard that is already indexed" do
    it "does not index" do
      calls = Atomic(Int32).new(0)

      with_indexer(succeeding_indexer(calls)) do
        shard = ShardFactory.create &.name("kemal")
          .at("github.com", "kemalcr", "kemal")
          .indexed_at(Time.utc)

        response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

        response.status_code.should eq(200)
        calls.get.should eq(0)
      end
    end
  end

  describe "a host failure" do
    it "renders the honest state and leaves the row reclaimable after the floor" do
      with_indexer(failing_indexer) do
        shard = ShardFactory.create &.name("kemal").at("github.com", "kemalcr", "kemal")

        response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

        response.status_code.should eq(200)
        response.body.should contain("found but not read yet")
        response.body.should contain("requested indexing")
        response.body.should_not contain("No tagged releases")
        response.body.should_not contain("repository has none")

        row = ShardQuery.new.id(shard.id).first
        row.indexed_at.should be_nil
        row.index_attempted_at.should_not be_nil
      end

      # Reclaimable after the floor: back-date the failed attempt past
      # RETRY_FLOOR and prove a later visit indexes it rather than refusing
      # forever.
      calls = Atomic(Int32).new(0)
      with_indexer(succeeding_indexer(calls)) do
        stale = ShardFactory.create &.name("radix")
          .at("github.com", "luislavena", "radix")
          .index_attempted_at(ShardIndexRequests::RETRY_FLOOR.ago - 1.minute)
          .index_error("timed out")

        BrowserClient.exec(Shards::Show.with(**identity_of(stale)))

        calls.get.should eq(1)
      end
    end
  end

  describe "a timeout" do
    it "renders the honest state and leaves the row reclaimable after the floor" do
      calls = Atomic(Int32).new(0)

      with_indexer(hanging_indexer(calls)) do
        ShardIndexRequests.inline_timeout = 10.milliseconds
        shard = ShardFactory.create &.name("kemal").at("github.com", "kemalcr", "kemal")

        response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

        response.status_code.should eq(200)
        response.body.should contain("found but not read yet")
        response.body.should contain("requested indexing")

        calls.get.should eq(1)
        row = ShardQuery.new.id(shard.id).first
        row.indexed_at.should be_nil
        row.index_attempted_at.should_not be_nil
      end
    end
  end

  # Everything below is about the show routes being spend endpoints.
  describe "spend is bounded by real shards, not by URLs" do
    it "commissions one indexing pass for a crawler hitting many invented version URLs under one cold shard" do
      calls = Atomic(Int32).new(0)

      with_indexer(succeeding_indexer(calls)) do
        shard = ShardFactory.create &.name("kemal").at("github.com", "kemalcr", "kemal")

        %w[1.0.0 2.0.0 nightly latest v9.9.9-invented].each do |invented|
          begin
            BrowserClient.exec(Shards::Versions::Show.with(**identity_of(shard), version: invented))
          rescue Lucky::RouteNotFoundError
            # Expected once the shard is indexed and 1.6.0 is its only real
            # version: every other invented string 404s. The commission
            # already ran, on the first request, before that check does.
          end
        end
        BrowserClient.exec(Shards::Show.with(**identity_of(shard)))

        calls.get.should eq(1)
      end
    end

    it "counts each shard separately, because each is real work" do
      calls = Atomic(Int32).new(0)

      with_indexer(succeeding_indexer(calls)) do
        kemal = ShardFactory.create &.name("kemal").at("github.com", "kemalcr", "kemal")
        radix = ShardFactory.create &.name("radix").at("github.com", "luislavena", "radix")

        BrowserClient.exec(Shards::Show.with(**identity_of(kemal)))
        BrowserClient.exec(Shards::Show.with(**identity_of(radix)))

        calls.get.should eq(2)
      end
    end
  end
end
