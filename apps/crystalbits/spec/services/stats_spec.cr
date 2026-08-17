require "../spec_helper"

# The rollup is the thing standing between raw page views and a public
# stats page, so every example here is about the numbers being literally
# true: a day is counted once, a person is counted once per day, today is
# never final, and a failure is retried without being hammered.
describe CrystalBits::Stats do
  before_each do
    StatsTestTables.prepare
    StatsTestTables.truncate
  end

  covered_through = -> {
    AppDatabase.query_one?("SELECT covered_through FROM stats_rollups WHERE name = 'daily_stats'", as: Time?)
  }

  raw_view_count = -> {
    AppDatabase.query_one("SELECT COUNT(*) FROM page_views", as: Int64)
  }

  stat_rows = ->(day : Time) {
    AppDatabase.query_all(
      "SELECT path_kind, views, visitors FROM daily_stats WHERE day = $1 ORDER BY path_kind, path",
      day.to_s("%F"), as: {String, Int64, Int64}
    )
  }

  describe "a first pass over three days of raw views" do
    it "rolls each ended day with its own totals" do
      plant_page_view("/posts/why-crystal", "post", stats_day(3), visitor: "a")
      plant_page_view("/posts/why-crystal", "post", stats_day(3), visitor: "b")
      plant_page_view("/", "home", stats_day(2), visitor: "a")
      plant_page_view("/posts/sharding-postgres", "post", stats_day(1), visitor: "a")
      plant_page_view("/posts/sharding-postgres", "post", stats_day(1), visitor: "b")
      plant_page_view("/", "home", stats_day(1), visitor: "b")

      CrystalBits::Stats.ensure_fresh.should be_true

      totals = CrystalBits::Stats.daily_totals(stats_day(3), stats_day(1))
      totals.size.should eq(3)
      totals[0].views.should eq(2)
      totals[0].visitors.should eq(2)
      totals[1].views.should eq(1)
      totals[1].visitors.should eq(1)
      totals[2].views.should eq(3)
      totals[2].visitors.should eq(2)
    end

    it "advances covered_through to yesterday" do
      plant_page_view("/posts/why-crystal", "post", stats_day(1))

      CrystalBits::Stats.ensure_fresh

      yesterday = stats_day(1)
      covered_through.call.should eq(Time.utc(yesterday.year, yesterday.month, yesterday.day))
    end
  end

  describe "a visitor seen twice in one day" do
    it "counts once in visitors and twice in views, per grain and for the day" do
      plant_page_view("/posts/why-crystal", "post", stats_day(1), visitor: "a")
      plant_page_view("/posts/why-crystal", "post", stats_day(1), visitor: "a")

      CrystalBits::Stats.ensure_fresh

      stat_rows.call(stats_day(1)).should contain({"post", 2_i64, 1_i64})
      stat_rows.call(stats_day(1)).should contain({"site", 2_i64, 1_i64})

      total = CrystalBits::Stats.daily_totals(stats_day(1), stats_day(1)).first
      total.views.should eq(2)
      total.visitors.should eq(1)
    end
  end

  describe "today" do
    it "is never rolled up, because it is still accumulating" do
      plant_page_view("/posts/why-crystal", "post", Time.utc, visitor: "a")

      CrystalBits::Stats.ensure_fresh.should be_true

      stat_rows.call(Time.utc).should be_empty
      CrystalBits::Stats.daily_totals(Time.utc, Time.utc).first.views.should eq(0)
      # The row is still raw, waiting to be rolled once the day has ended.
      raw_view_count.call.should eq(1)
    end
  end

  describe "the retry floor" do
    it "lets a failed pass be reclaimed only after the floor" do
      calls = 0
      original = CrystalBits::Stats.runner
      CrystalBits::Stats.runner = -> { calls += 1; raise "boom" }
      begin
        CrystalBits::Stats.ensure_fresh.should be_false
        CrystalBits::Stats.ensure_fresh.should be_false
        CrystalBits::Stats.ensure_fresh.should be_false
        calls.should eq(1)
      ensure
        CrystalBits::Stats.runner = original
      end

      # The failure is on the claim row, and covered_through did not move.
      AppDatabase.query_one("SELECT last_error FROM stats_rollups WHERE name = 'daily_stats'", as: String?).should eq("boom")
      covered_through.call.should be_nil

      # Once the floor has passed, the same claim is winnable again.
      AppDatabase.exec(
        "UPDATE stats_rollups SET claimed_at = $1 WHERE name = 'daily_stats'",
        CrystalBits::Stats::RETRY_FLOOR.ago - 1.minute
      )

      plant_page_view("/posts/why-crystal", "post", stats_day(1))
      CrystalBits::Stats.ensure_fresh.should be_true
      CrystalBits::Stats.daily_totals(stats_day(1), stats_day(1)).first.views.should eq(1)
      AppDatabase.query_one("SELECT last_error FROM stats_rollups WHERE name = 'daily_stats'", as: String?).should be_nil
    end

    it "never redoes a pass that already succeeded" do
      calls = 0
      original = CrystalBits::Stats.runner
      CrystalBits::Stats.runner = -> { calls += 1; original.call }
      begin
        plant_page_view("/posts/why-crystal", "post", stats_day(1))

        CrystalBits::Stats.ensure_fresh.should be_true
        CrystalBits::Stats.ensure_fresh.should be_true
        CrystalBits::Stats.ensure_fresh.should be_true

        calls.should eq(1)
      ensure
        CrystalBits::Stats.runner = original
      end
    end

    it "claims the pass for exactly one of several concurrent readers" do
      plant_page_view("/posts/why-crystal", "post", stats_day(1))

      calls = 0
      original = CrystalBits::Stats.runner
      CrystalBits::Stats.runner = -> { calls += 1; original.call }
      done = Channel(Nil).new
      begin
        6.times do
          spawn do
            CrystalBits::Stats.ensure_fresh
          ensure
            done.send(nil)
          end
        end
        6.times { done.receive }

        calls.should eq(1)
      ensure
        CrystalBits::Stats.runner = original
      end
    end
  end

  describe "a pass that will not finish in time" do
    it "gives up waiting rather than hanging the render" do
      original_runner = CrystalBits::Stats.runner
      original_timeout = CrystalBits::Stats.rollup_timeout
      CrystalBits::Stats.rollup_timeout = 50.milliseconds
      CrystalBits::Stats.runner = -> { sleep 2.seconds; true }
      begin
        started = Time.monotonic

        CrystalBits::Stats.ensure_fresh.should be_false

        (Time.monotonic - started).should be < 1.second
      ensure
        CrystalBits::Stats.rollup_timeout = original_timeout
        CrystalBits::Stats.runner = original_runner
      end
    end
  end

  describe "re-rolling a covered day" do
    it "overwrites the grain instead of double counting it" do
      plant_page_view("/posts/why-crystal", "post", stats_day(2), visitor: "a")
      plant_page_view("/posts/why-crystal", "post", stats_day(1), visitor: "a")
      CrystalBits::Stats.ensure_fresh

      # Send the claim row two days back, as if those days had never been
      # rolled, and age the claim past the floor.
      AppDatabase.exec(
        "UPDATE stats_rollups SET covered_through = $1::date, claimed_at = $2 WHERE name = 'daily_stats'",
        stats_day(3).to_s("%F"), CrystalBits::Stats::RETRY_FLOOR.ago - 1.minute
      )

      CrystalBits::Stats.ensure_fresh.should be_true

      total = CrystalBits::Stats.daily_totals(stats_day(2), stats_day(2)).first
      total.views.should eq(1)
      total.visitors.should eq(1)
    end
  end

  describe "pruning" do
    it "removes raw rows past the window and keeps newer ones" do
      plant_page_view("/posts/old-post", "post", stats_day(31), visitor: "a")
      plant_page_view("/posts/recent-post", "post", stats_day(29), visitor: "a")

      CrystalBits::Stats.ensure_fresh

      AppDatabase.query_all("SELECT path FROM page_views", as: String).should eq(["/posts/recent-post"])
      # The pruned day was rolled before it was deleted, so its numbers
      # survive in daily_stats.
      CrystalBits::Stats.daily_totals(stats_day(31), stats_day(31)).first.views.should eq(1)
    end
  end

  describe "the breakdowns the page renders" do
    it "ranks the most read paths of a kind, most views first" do
      3.times { |i| plant_page_view("/posts/why-crystal", "post", stats_day(2), visitor: "v#{i}") }
      plant_page_view("/posts/sharding-postgres", "post", stats_day(1), visitor: "a")
      plant_page_view("/", "home", stats_day(1), visitor: "a")

      CrystalBits::Stats.ensure_fresh

      paths = CrystalBits::Stats.top_paths("post", stats_day(7), stats_day(1))
      paths.map(&.path).should eq(["/posts/why-crystal", "/posts/sharding-postgres"])
      paths.first.views.should eq(3)
      paths.first.visitors.should eq(3)

      CrystalBits::Stats.top_paths("post", stats_day(7), stats_day(1), limit: 1).size.should eq(1)
    end

    it "ranks several kinds together when the page reads them as one list" do
      plant_page_view("/posts/why-crystal", "post", stats_day(1), visitor: "a")
      plant_page_view("/", "home", stats_day(1), visitor: "a")
      plant_page_view("/", "home", stats_day(1), visitor: "b")
      plant_page_view("/about", "other", stats_day(1), visitor: "a")

      CrystalBits::Stats.ensure_fresh

      paths = CrystalBits::Stats.top_paths(["post", "home"], stats_day(7), stats_day(1))
      paths.map(&.path).should eq(["/", "/posts/why-crystal"])
    end

    it "ranks referrer hosts, with direct as its own bucket" do
      plant_page_view("/posts/why-crystal", "post", stats_day(1), visitor: "a", referrer_host: "reddit.com")
      plant_page_view("/posts/why-crystal", "post", stats_day(1), visitor: "b", referrer_host: "reddit.com")
      plant_page_view("/posts/sharding-postgres", "post", stats_day(1), visitor: "c")

      CrystalBits::Stats.ensure_fresh

      referrers = CrystalBits::Stats.top_referrers(stats_day(7), stats_day(1))
      referrers.map(&.referrer_host).should eq(["reddit.com", "direct"])
      referrers.first.views.should eq(2)
    end

    it "ranks countries, with unknown for views that carried no geo header" do
      plant_page_view("/posts/why-crystal", "post", stats_day(1), visitor: "a", country: "US")
      plant_page_view("/posts/sharding-postgres", "post", stats_day(1), visitor: "b")

      CrystalBits::Stats.ensure_fresh

      countries = CrystalBits::Stats.top_countries(stats_day(7), stats_day(1))
      countries.map(&.country).should contain("US")
      countries.map(&.country).should contain("unknown")
    end
  end

  describe ".previous_period" do
    it "is the same length window immediately before" do
      previous = CrystalBits::Stats.previous_period(stats_day(7), stats_day(4))

      yesterday_of_previous = stats_day(8)
      first_of_previous = stats_day(11)
      previous[:to].should eq(Time.utc(yesterday_of_previous.year, yesterday_of_previous.month, yesterday_of_previous.day))
      previous[:from].should eq(Time.utc(first_of_previous.year, first_of_previous.month, first_of_previous.day))
    end
  end

  describe ".covered_through" do
    it "is nil before the first pass and yesterday after it" do
      CrystalBits::Stats.covered_through.should be_nil

      CrystalBits::Stats.ensure_fresh

      yesterday = stats_day(1)
      CrystalBits::Stats.covered_through.should eq(Time.utc(yesterday.year, yesterday.month, yesterday.day))
    end
  end
end
