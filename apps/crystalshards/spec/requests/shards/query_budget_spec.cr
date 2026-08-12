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

  # The listing sorts by popularity, and that ORDER BY is a correlated subquery
  # over dependencies, so `dependent_shard_id` legitimately appears in the
  # pagination count and in the page query as well as in the bulk count. Three
  # mentions is correct; what must never happen is that number growing with the
  # page, which is what an N+1 looks like from here.
  #
  # The bulk count is the one statement that aggregates, so it is identified by
  # its GROUP BY rather than by a total that would change if the default sort
  # ever did.
  it "counts dependents for the whole page in a single aggregate, whatever the page size" do
    2.times { |i| ShardFactory.create &.name("few-#{i}") }
    few = QueryCounter.record { BrowserClient.exec(Shards::Index) }

    18.times { |i| ShardFactory.create &.name("many-#{i}") }
    many = QueryCounter.record { BrowserClient.exec(Shards::Index) }

    aggregate = ->(queries : Array(String)) do
      queries.count { |q| q.includes?("dependent_shard_id") && q.includes?("GROUP BY") }
    end

    aggregate.call(few).should eq(1)
    aggregate.call(many).should eq(1)

    # And the total number of statements touching the edge table is flat too, so
    # a per-card lookup added later cannot hide behind the aggregate assertion.
    mentions = ->(queries : Array(String)) { queries.count(&.includes?("dependent_shard_id")) }
    mentions.call(many).should eq(mentions.call(few))
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
