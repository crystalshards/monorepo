require "../spec_helper"

# The rollup is the thing standing between raw page views and a public
# stats page, so every example here is about the numbers being literally
# true: a day is counted once, a person is counted once per day, today is
# never final, and a failure is retried without being hammered.
describe CrystalDocs::Stats do
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
      plant_page_view("/docs/kemal", "package", stats_day(3), visitor: "a")
      plant_page_view("/docs/kemal", "package", stats_day(3), visitor: "b")
      plant_page_view("/docs/kemal/1.6.0", "docs_version", stats_day(2), visitor: "a")
      plant_page_view("/docs/semver", "package", stats_day(1), visitor: "a")
      plant_page_view("/docs/semver", "package", stats_day(1), visitor: "b")
      plant_page_view("/docs/semver/2.0.0", "docs_version", stats_day(1), visitor: "b")

      CrystalDocs::Stats.ensure_fresh.should be_true

      totals = CrystalDocs::Stats.daily_totals(stats_day(3), stats_day(1))
      totals.size.should eq(3)
      totals[0].views.should eq(2)
      totals[0].visitors.should eq(2)
      totals[1].views.should eq(1)
      totals[1].visitors.should eq(1)
      totals[2].views.should eq(3)
      totals[2].visitors.should eq(2)
    end

    it "advances covered_through to yesterday" do
      plant_page_view("/docs/kemal", "package", stats_day(1))

      CrystalDocs::Stats.ensure_fresh

      yesterday = stats_day(1)
      covered_through.call.should eq(Time.utc(yesterday.year, yesterday.month, yesterday.day))
    end
  end

  describe "a visitor seen twice in one day" do
    it "counts once in visitors and twice in views, per grain and for the day" do
      plant_page_view("/docs/kemal", "package", stats_day(1), visitor: "a")
      plant_page_view("/docs/kemal", "package", stats_day(1), visitor: "a")

      CrystalDocs::Stats.ensure_fresh

      stat_rows.call(stats_day(1)).should contain({"package", 2_i64, 1_i64})
      stat_rows.call(stats_day(1)).should contain({"site", 2_i64, 1_i64})

      total = CrystalDocs::Stats.daily_totals(stats_day(1), stats_day(1)).first
      total.views.should eq(2)
      total.visitors.should eq(1)
    end
  end

  describe "today" do
    it "is never rolled up, because it is still accumulating" do
      plant_page_view("/docs/kemal", "package", Time.utc, visitor: "a")

      CrystalDocs::Stats.ensure_fresh.should be_true

      stat_rows.call(Time.utc).should be_empty
      CrystalDocs::Stats.daily_totals(Time.utc, Time.utc).first.views.should eq(0)
      # The row is still raw, waiting to be rolled once the day has ended.
      raw_view_count.call.should eq(1)
    end
  end

  describe "the retry floor" do
    it "lets a failed pass be reclaimed only after the floor" do
      calls = 0
      original = CrystalDocs::Stats.runner
      CrystalDocs::Stats.runner = -> { calls += 1; raise "boom" }
      begin
        CrystalDocs::Stats.ensure_fresh.should be_false
        CrystalDocs::Stats.ensure_fresh.should be_false
        CrystalDocs::Stats.ensure_fresh.should be_false
        calls.should eq(1)
      ensure
        CrystalDocs::Stats.runner = original
      end

      # The failure is on the claim row, and covered_through did not move.
      AppDatabase.query_one("SELECT last_error FROM stats_rollups WHERE name = 'daily_stats'", as: String?).should eq("boom")
      covered_through.call.should be_nil

      # Once the floor has passed, the same claim is winnable again.
      AppDatabase.exec(
        "UPDATE stats_rollups SET claimed_at = $1 WHERE name = 'daily_stats'",
        CrystalDocs::Stats::RETRY_FLOOR.ago - 1.minute
      )

      plant_page_view("/docs/kemal", "package", stats_day(1))
      CrystalDocs::Stats.ensure_fresh.should be_true
      CrystalDocs::Stats.daily_totals(stats_day(1), stats_day(1)).first.views.should eq(1)
      AppDatabase.query_one("SELECT last_error FROM stats_rollups WHERE name = 'daily_stats'", as: String?).should be_nil
    end

    it "never redoes a pass that already succeeded" do
      calls = 0
      original = CrystalDocs::Stats.runner
      CrystalDocs::Stats.runner = -> { calls += 1; original.call }
      begin
        plant_page_view("/docs/kemal", "package", stats_day(1))

        CrystalDocs::Stats.ensure_fresh.should be_true
        CrystalDocs::Stats.ensure_fresh.should be_true
        CrystalDocs::Stats.ensure_fresh.should be_true

        calls.should eq(1)
      ensure
        CrystalDocs::Stats.runner = original
      end
    end

    it "claims the pass for exactly one of several concurrent readers" do
      plant_page_view("/docs/kemal", "package", stats_day(1))

      calls = 0
      original = CrystalDocs::Stats.runner
      CrystalDocs::Stats.runner = -> { calls += 1; original.call }
      done = Channel(Nil).new
      begin
        6.times do
          spawn do
            CrystalDocs::Stats.ensure_fresh
          ensure
            done.send(nil)
          end
        end
        6.times { done.receive }

        calls.should eq(1)
      ensure
        CrystalDocs::Stats.runner = original
      end
    end
  end

  describe "a pass that will not finish in time" do
    it "gives up waiting rather than hanging the render" do
      original_runner = CrystalDocs::Stats.runner
      original_timeout = CrystalDocs::Stats.rollup_timeout
      CrystalDocs::Stats.rollup_timeout = 50.milliseconds
      CrystalDocs::Stats.runner = -> { sleep 2.seconds; true }
      begin
        started = Time.monotonic

        CrystalDocs::Stats.ensure_fresh.should be_false

        (Time.monotonic - started).should be < 1.second
      ensure
        CrystalDocs::Stats.rollup_timeout = original_timeout
        CrystalDocs::Stats.runner = original_runner
      end
    end
  end

  describe "re-rolling a covered day" do
    it "overwrites the grain instead of double counting it" do
      plant_page_view("/docs/kemal", "package", stats_day(2), visitor: "a")
      plant_page_view("/docs/kemal", "package", stats_day(1), visitor: "a")
      CrystalDocs::Stats.ensure_fresh

      # Send the claim row two days back, as if those days had never been
      # rolled, and age the claim past the floor.
      AppDatabase.exec(
        "UPDATE stats_rollups SET covered_through = $1::date, claimed_at = $2 WHERE name = 'daily_stats'",
        stats_day(3).to_s("%F"), CrystalDocs::Stats::RETRY_FLOOR.ago - 1.minute
      )

      CrystalDocs::Stats.ensure_fresh.should be_true

      total = CrystalDocs::Stats.daily_totals(stats_day(2), stats_day(2)).first
      total.views.should eq(1)
      total.visitors.should eq(1)
    end
  end

  describe "pruning" do
    it "removes raw rows past the window and keeps newer ones" do
      plant_page_view("/docs/old", "package", stats_day(31), visitor: "a")
      plant_page_view("/docs/recent", "package", stats_day(29), visitor: "a")

      CrystalDocs::Stats.ensure_fresh

      AppDatabase.query_all("SELECT path FROM page_views", as: String).should eq(["/docs/recent"])
      # The pruned day was rolled before it was deleted, so its numbers
      # survive in daily_stats.
      CrystalDocs::Stats.daily_totals(stats_day(31), stats_day(31)).first.views.should eq(1)
    end
  end

  describe "docs.total_views" do
    it "is rewritten from rolled views, replacing the bot count" do
      kemal = DocFactory.create &.package_name("kemal").total_views(999)
      unread = DocFactory.create &.package_name("unread").total_views(500)

      plant_page_view("/docs/kemal", "package", stats_day(2), visitor: "a")
      plant_page_view("/docs/kemal/1.6.0", "docs_version", stats_day(2), visitor: "b")
      plant_page_view("/docs/kemal/1.6.0/Kemal/Config", "docs_type", stats_day(1), visitor: "a")
      # A repository-addressed front carries no package name in its path and
      # is deliberately not attributed.
      plant_page_view("/docs/_/github.com/kemalcr/kemal/1.6.0", "docs_version", stats_day(1), visitor: "c")

      CrystalDocs::Stats.ensure_fresh

      DocQuery.new.package_name("kemal").first.total_views.should eq(3)
      DocQuery.new.package_name("unread").first.total_views.should eq(0)
    end
  end

  describe "the breakdowns the page renders" do
    it "ranks the most read paths of a kind, most views first" do
      3.times { |i| plant_page_view("/docs/kemal", "package", stats_day(2), visitor: "v#{i}") }
      plant_page_view("/docs/semver", "package", stats_day(1), visitor: "a")
      plant_page_view("/docs/kemal/1.6.0", "docs_version", stats_day(1), visitor: "a")

      CrystalDocs::Stats.ensure_fresh

      paths = CrystalDocs::Stats.top_paths("package", stats_day(7), stats_day(1))
      paths.map(&.path).should eq(["/docs/kemal", "/docs/semver"])
      paths.first.views.should eq(3)
      paths.first.visitors.should eq(3)

      CrystalDocs::Stats.top_paths("package", stats_day(7), stats_day(1), limit: 1).size.should eq(1)
    end

    it "ranks several kinds together when the page reads them as one list" do
      plant_page_view("/docs/kemal/1.6.0", "docs_version", stats_day(1), visitor: "a")
      plant_page_view("/docs/kemal/1.6.0/Kemal/Config", "docs_type", stats_day(1), visitor: "a")
      plant_page_view("/docs/kemal/1.6.0/Kemal/Config", "docs_type", stats_day(1), visitor: "b")
      plant_page_view("/docs/kemal", "package", stats_day(1), visitor: "a")

      CrystalDocs::Stats.ensure_fresh

      paths = CrystalDocs::Stats.top_paths(["docs_version", "docs_type"], stats_day(7), stats_day(1))
      paths.map(&.path).should eq(["/docs/kemal/1.6.0/Kemal/Config", "/docs/kemal/1.6.0"])
    end

    it "ranks referrer hosts, with direct as its own bucket" do
      plant_page_view("/docs/kemal", "package", stats_day(1), visitor: "a", referrer_host: "reddit.com")
      plant_page_view("/docs/kemal", "package", stats_day(1), visitor: "b", referrer_host: "reddit.com")
      plant_page_view("/docs/semver", "package", stats_day(1), visitor: "c")

      CrystalDocs::Stats.ensure_fresh

      referrers = CrystalDocs::Stats.top_referrers(stats_day(7), stats_day(1))
      referrers.map(&.referrer_host).should eq(["reddit.com", "direct"])
      referrers.first.views.should eq(2)
    end

    it "ranks countries, with unknown for views that carried no geo header" do
      plant_page_view("/docs/kemal", "package", stats_day(1), visitor: "a", country: "US")
      plant_page_view("/docs/semver", "package", stats_day(1), visitor: "b")

      CrystalDocs::Stats.ensure_fresh

      countries = CrystalDocs::Stats.top_countries(stats_day(7), stats_day(1))
      countries.map(&.country).should contain("US")
      countries.map(&.country).should contain("unknown")
    end
  end

  describe ".previous_period" do
    it "is the same length window immediately before" do
      previous = CrystalDocs::Stats.previous_period(stats_day(7), stats_day(4))

      yesterday_of_previous = stats_day(8)
      first_of_previous = stats_day(11)
      previous[:to].should eq(Time.utc(yesterday_of_previous.year, yesterday_of_previous.month, yesterday_of_previous.day))
      previous[:from].should eq(Time.utc(first_of_previous.year, first_of_previous.month, first_of_previous.day))
    end
  end

  describe ".covered_through" do
    it "is nil before the first pass and yesterday after it" do
      CrystalDocs::Stats.covered_through.should be_nil

      CrystalDocs::Stats.ensure_fresh

      yesterday = stats_day(1)
      CrystalDocs::Stats.covered_through.should eq(Time.utc(yesterday.year, yesterday.month, yesterday.day))
    end
  end
end
