require "../spec_helper"

# The public /stats page. The tables it reads are planted row by row: the
# collector, the rollup service and the Search Console client own the writes,
# and these specs only depend on the shared schema's shapes.
#
# The action rolls up lazily on read, which is right in production and wrong
# here: a real pass would find nothing pending in an empty page_views, mark
# the claim covered through yesterday, and clear the very last_error one of
# these examples plants to prove the page states a lag. The rollup's own
# specs exercise that path; these exercise what the page does with a given
# state, so the pass is off for the whole file and restored after it.
describe "Stats::Index" do
  around_each do |example|
    CrystalDocs::Stats.lazy_rollup = false
    begin
      example.run
    ensure
      CrystalDocs::Stats.lazy_rollup = true
    end
  end

  before_each do
    StatsTestTables.prepare
    StatsTestTables.truncate
    # StatsTestTables predates this table's migration and does not name it;
    # the Search Console examples below plant it row by row.
    AppDatabase.exec("DELETE FROM search_console_daily")
  end

  describe "with no data at all" do
    it "says so instead of rendering zeros" do
      response = BrowserClient.exec(Stats::Index)

      response.status_code.should eq(200)
      response.body.should contain("<title>Site statistics - CrystalDocs.org</title>")
      response.body.should contain("No visits recorded in this period")
      response.body.should contain("has not recorded any visits yet")
      # A flatlined chart here would claim thirty measured quiet days, so
      # there is no chart in this state.
      response.body.should_not contain(%(<svg))
      # And no zero standing in for an absence anywhere else either.
      response.body.should contain("Nothing read in this period")
    end

    it "distinguishes its own first day from having recorded nothing" do
      # The row for the request that renders the page is exactly the case:
      # nothing has rolled, so every rolled number is genuinely absent, but
      # "no visits recorded" would be a false statement about this very
      # reader.
      plant_page_view("/", "home", Time.utc, visitor: "a")

      response = BrowserClient.exec(Stats::Index)

      response.body.should contain("Counting began")
      response.body.should contain("appear here tomorrow")
      response.body.should_not contain("has not recorded any visits yet")
      # The rolled sections are still empty, and still say so.
      response.body.should contain("No visits recorded in this period")
      response.body.should_not contain(%(<svg))
    end

    it "still offers the period selector" do
      response = BrowserClient.exec(Stats::Index)

      response.body.should contain("/stats?period=7")
      response.body.should contain("/stats?period=90")
      response.body.should contain(%(aria-current="true"))
    end

    it "says Search Console is not configured rather than showing an empty table" do
      response = BrowserClient.exec(Stats::Index)

      response.body.should contain("not linked to Google Search Console")
      response.body.should_not contain("Impressions")
    end
  end

  describe "with data" do
    it "renders the chart, its table equivalent, and every section" do
      plant_rollup("daily_stats", covered_through: days_ago(1))
      10.times do |n|
        plant_site_day(days_ago(n), views: (50 + n * 7).to_i64, visitors: (20 + n * 3).to_i64)
      end
      plant_grain(days_ago(2), "package", "/docs/kemal", "github.com", "us", views: 120_i64, visitors: 80_i64)
      plant_grain(days_ago(1), "docs_version", "/docs/kemal/1.6.0", "news.ycombinator.com", "de", views: 60_i64, visitors: 40_i64)
      plant_grain(days_ago(1), "docs_type", "/docs/kemal/1.6.0/Kemal/Config", "github.com", "us", views: 45_i64, visitors: 30_i64)
      plant_grain(days_ago(1), "package", "/docs/lucky", "github.com", "us", views: 90_i64, visitors: 70_i64)
      # Not one of the kinds this page reads, and the most viewed row
      # planted: if a kind outside package/docs_version/docs_type ever
      # leaked into the list, this row would top it.
      plant_grain(days_ago(3), "home", "/", "direct", "jp", views: 200_i64, visitors: 150_i64)

      response = BrowserClient.exec(Stats::Index)

      response.status_code.should eq(200)
      # The chart and its text equivalent carry the same numbers: one date
      # cell per window day in the table under the chart.
      response.body.should contain(%(<svg))
      response.body.should contain("Daily figures as a table")
      chart_days(response.body).should eq(30)
      # What people read: the three documentation kinds, ranked by views,
      # linked by verbatim request path.
      response.body.should contain(%(href="/docs/kemal"))
      response.body.should contain(%(href="/docs/kemal/1.6.0"))
      response.body.should contain(%(href="/docs/kemal/1.6.0/Kemal/Config"))
      response.body.should contain(%(href="/docs/lucky"))
      kemal_at = response.body.index(%(href="/docs/kemal")).not_nil!
      lucky_at = response.body.index(%(href="/docs/lucky")).not_nil!
      kemal_at.should be < lucky_at
      # The home page is counted but is not documentation, so the most-read
      # list never ranks it.
      response.body.should_not contain(%(<a href="/">/</a>))
      # Where they came from: referrers ranked, direct stated as a share.
      response.body.should contain("github.com")
      response.body.should contain("news.ycombinator.com")
      response.body.should contain("arrived directly")
      # Reach.
      response.body.should contain("US")
      response.body.should contain("DE")
    end

    it "labels the visitor column on lists as a sum of daily uniques" do
      plant_site_day(days_ago(1), views: 10_i64, visitors: 4_i64)
      plant_grain(days_ago(1), "package", "/docs/kemal", "github.com", "us", views: 10_i64, visitors: 4_i64)

      response = BrowserClient.exec(Stats::Index)

      response.body.should contain("daily unique")
    end

    it "restricts the window when the period changes" do
      plant_site_day(days_ago(3), views: 40_i64, visitors: 20_i64)
      plant_site_day(days_ago(20), views: 99_i64, visitors: 50_i64)
      plant_grain(days_ago(20), "package", "/docs/old-favourite", "github.com", "us", views: 99_i64, visitors: 50_i64)

      week = BrowserClient.exec(Stats::Index.with(period: "7"))
      chart_days(week.body).should eq(7)
      week.body.should_not contain("old-favourite")

      month = BrowserClient.exec(Stats::Index.with(period: "30"))
      chart_days(month.body).should eq(30)
      month.body.should contain("old-favourite")
    end

    it "falls back to 30 days for a period the page does not offer" do
      response = BrowserClient.exec(Stats::Index.with(period: "13"))

      response.status_code.should eq(200)
      response.body.should contain("/stats?period=7")
    end

    it "states the counting lag rather than rendering it as a dip" do
      plant_rollup("daily_stats", covered_through: days_ago(4), last_error: "boom")
      plant_site_day(days_ago(4), views: 30_i64, visitors: 12_i64)

      response = BrowserClient.exec(Stats::Index)

      response.body.should contain("Counting is temporarily behind")
      response.body.should contain("numbers run through")
    end
  end

  describe "Search Console section" do
    it "waits honestly when linked but never fetched" do
      with_search_console_property do
        response = BrowserClient.exec(Stats::Index)

        response.body.should contain("Waiting on the first fetch from Google")
        response.body.should_not contain("Impressions")
      end
    end

    it "renders queries with Google's label and the coverage date" do
      with_search_console_property do
        plant_rollup("search_console", covered_through: days_ago(3))
        plant_query(days_ago(3), "crystal docs", "https://crystaldocs.org/docs/kemal",
          clicks: 42_i64, impressions: 900_i64, position: 3.4)
        plant_query(days_ago(4), "crystal docs", "https://crystaldocs.org/docs/kemal",
          clicks: 8_i64, impressions: 100_i64, position: 9.0)
        plant_query(days_ago(3), "shard documentation", "https://crystaldocs.org/",
          clicks: 30_i64, impressions: 500_i64, position: 1.8)

        response = BrowserClient.exec(Stats::Index)

        # The attribution names Google as the source. Asserted without the
        # apostrophe of "Google's": the renderer escapes it to &#39; and a
        # raw one could never match a rendered page.
        response.body.should contain("From Google Search Console")
        response.body.should contain("crystal docs")
        response.body.should contain("shard documentation")
        # Clicks summed across days: 42 + 8.
        response.body.should contain(%(<td class="num">50</td>))
        # Position is impressions-weighted, not a flat average:
        # (3.4*900 + 9.0*100) / 1000 = 3.96 -> 4.0
        response.body.should contain(%(<td class="num">4.0</td>))
        response.body.should contain("through #{days_ago(3).to_s("%b %-d, %Y")}")
      end
    end

    it "reports a failed fetch without rendering the stored figures as vanished" do
      with_search_console_property do
        plant_rollup("search_console", covered_through: days_ago(6), last_error: "403 from Google")
        plant_query(days_ago(6), "crystal api docs", "https://crystaldocs.org/",
          clicks: 5_i64, impressions: 60_i64, position: 11.0)

        response = BrowserClient.exec(Stats::Index)

        response.body.should contain("The latest fetch from Google failed")
        response.body.should contain(days_ago(6).to_s("%b %-d, %Y"))
        # The stored figures are still shown, dated.
        response.body.should contain("crystal api docs")
      end
    end
  end

  # SEARCH_CONSOLE_PROPERTY states use the with_search_console_property
  # helper from spec/support, which restores the environment after itself.
end
