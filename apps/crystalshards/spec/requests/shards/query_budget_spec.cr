require "../../spec_helper"

# Avram publishes one QueryEvent per SQL statement it issues, so counting the
# events around a request measures the real query count rather than estimating
# it from the code.
#
# Pulsar subscriptions are global and cannot be removed, so the subscriber is
# installed once and only collects while a recording buffer is set.
module QueryCounter
  class_property recording : Array(String)? = nil

  def self.record(&) : Array(String)
    buffer = [] of String
    self.recording = buffer

    begin
      yield
    ensure
      self.recording = nil
    end

    buffer
  end
end

Avram::Events::QueryEvent.subscribe do |event, _duration|
  QueryCounter.recording.try(&.<<(event.query))
end

describe "shard listing query budget" do
  # The point of the bulk dependent count. Every card shows a dependent
  # figure, and resolving it per card would make the query count track the
  # length of the page.
  it "costs the same number of queries for 20 shards as for 2" do
    2.times { |i| ShardFactory.create &.name("small-#{i}").github_stars(i) }
    small = QueryCounter.record { BrowserClient.exec(Shards::Index) }

    18.times { |i| ShardFactory.create &.name("large-#{i}").github_stars(i) }
    large = QueryCounter.record { BrowserClient.exec(Shards::Index) }

    # Confirm the second request really did render a full page, so this is not
    # two identically cheap empty renders agreeing with each other.
    ShardQuery.new.select_count.should eq(20)
    large.size.should eq(small.size)
  end

  it "renders a full page of shards in four queries" do
    20.times { |i| ShardFactory.create &.name("shard-#{i}").github_stars(i) }

    queries = QueryCounter.record { BrowserClient.exec(Shards::Index) }

    # count for pagination, the page of shards, the preloaded versions, and
    # one bulk dependent count. An N+1 on either versions or dependents would
    # push this to 20-something and fail here.
    queries.size.should eq(4)
  end

  it "counts dependents for the whole page in a single statement" do
    20.times { |i| ShardFactory.create &.name("shard-#{i}") }

    queries = QueryCounter.record { BrowserClient.exec(Shards::Index) }

    queries.count(&.includes?("dependent_shard_id")).should eq(1)
  end

  it "keeps the homepage flat across both card sections" do
    10.times { |i| ShardFactory.create &.name("home-#{i}").github_stars(i) }

    queries = QueryCounter.record { BrowserClient.exec(Home::Index) }

    # star totals, dependency link total, shard count, featured, featured
    # versions, recent, recent versions, and one dependent count covering both
    # sections.
    queries.size.should eq(8)
    queries.count(&.includes?("dependent_shard_id")).should eq(2)
  end
end
