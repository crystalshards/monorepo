# The read half of first-party stats, and the only thing the public /stats
# page queries.
#
# It reads three tables this app owns under the stats contract:
#
#   daily_stats           the rollup. Two row shapes per rolled day:
#                         full-grain rows, one per observed
#                         (day, path_kind, path, referrer_host, country), and
#                         exactly one site totals row per day, marked
#                         path_kind='site' with the other dimensions blank.
#   stats_rollups         claim rows. covered_through is the last day whose
#                         numbers are settled; last_error marks a failed job.
#   search_console_daily  Google's numbers, keyed by (day, query, page).
#
# Two honesty rules shape every query here:
#
#   A count of PEOPLE only ever comes from a 'site' row. Its visitors column
#   is COUNT(DISTINCT visitor_hash) over the whole day, exact because the
#   rollup still had the raw hashes when it computed it. Summing the visitors
#   of grain rows is never a count of people: one reader who views three
#   packages appears in three grains. The top lists below do sum grain rows,
#   and their visitors column is therefore labelled a sum of daily uniques,
#   not a period-unique count (range-unique is unrecoverable once the raw
#   table prunes, which it does after 30 days).
#
#   Absence is never rendered as a number. The page gets nilable coverage
#   markers (first_counted_day, counted_through, SearchConsole's configured
#   flag) so it can say "not recording yet" or "not configured" rather than
#   print a zero that reads as a verdict.
module StatsReport
  # The periods the page offers, in days, and the one an absent or
  # unrecognised `period` parameter falls back to. 90 is the longest window
  # offered: the raw table prunes at 30 days, and while rolled views stay
  # exact forever, a longer window invites reading the chart's visitor line
  # as comparable to a commercial product's uniques, which it is not.
  PERIODS        = [7, 30, 90]
  DEFAULT_PERIOD = 30

  # One day of the chart. `day` is a DATE column decoded by crystal-pg as a
  # Time at midnight; the page only ever formats it.
  record DayCount, day : Time, views : Int64, visitors : Int64

  # A row of a "most read" list. `path` is the request path verbatim, so the
  # page can link it without reconstructing a route.
  record PageCount, path : String, views : Int64, visitors : Int64

  # A referrer host. 'direct' is excluded by `top_referrers` and reported
  # separately: it is the absence of a referrer, not a source.
  record ReferrerCount, host : String, views : Int64, visitors : Int64

  # A country code as the load balancer's geo header supplied it, or 'unknown'
  # when it supplied nothing.
  record CountryCount, code : String, views : Int64, visitors : Int64

  # One Search Console query. `position` is the impressions-weighted mean of
  # the daily positions, which is the only average of a ratio that stays
  # honest: an unweighted mean would let a one-impression day at position 90
  # cancel a thousand-impression day at position 3.
  record QueryCount, query : String, clicks : Int64, impressions : Int64, position : Float64

  # Everything the Search Console section needs to pick one of its honest
  # states. `configured` keys on the same env var the fetch client requires.
  # covered_through comes from the claim row, NOT from MAX(day) of the data
  # table: a day with genuinely zero impressions stores no rows, and MAX(day)
  # would read that true zero as missing data. Days past covered_through are
  # "Google has not settled them yet", never "nobody clicked".
  record SearchConsole,
    configured : Bool,
    covered_through : Time?,
    last_error : String?,
    queries : Array(QueryCount)

  # The aggregate the action hands the page. Everything nilable is nil exactly
  # when the honest answer is "we do not know", and the page says so.
  class Report
    getter days : Int32
    getter from : Time
    getter to : Time

    # One entry per calendar day of the window, zero-filled. A zero-filled
    # day before counting started is distinguished from a true zero by
    # `first_counted_day`, which the page prints as the coverage note.
    getter daily : Array(DayCount)
    getter top_pages : Array(PageCount)
    getter referrers : Array(ReferrerCount)

    # Views with no referring site, kept apart from `referrers` so the page
    # can state the direct share instead of ranking "direct" as if it were
    # a source.
    getter direct_views : Int64
    getter countries : Array(CountryCount)
    getter search_console : SearchConsole

    # The first and last day the rollup has ever produced numbers for, from
    # the claim row where it exists and the data itself where it does not.
    # Both nil together means the rollup has produced nothing yet, which is
    # not the same fact as having recorded nothing.
    getter first_counted_day : Time?
    getter counted_through : Time?

    # When the collector's own table holds rows that no rollup has reached,
    # the moment the earliest of them arrived; nil once a day has rolled, and
    # nil when nothing has ever been recorded. This is what separates a site
    # on its first day from a site that is not counting: without it the page
    # would tell a reader it recorded no visits while holding the row for
    # the very request that rendered the sentence.
    getter recording_since : Time?

    # True when the counting pipeline's own claim row carries a failure. The
    # page renders this as "counting is behind", never as a dip toward zero.
    getter counting_error : Bool

    def initialize(
      @days, @from, @to, @daily, @top_pages, @referrers, @direct_views,
      @countries, @search_console, @first_counted_day, @counted_through,
      @counting_error, @recording_since = nil,
    )
    end

    # Exact: views is additive across every grain of the rollup.
    def total_views : Int64
      daily.sum(0_i64, &.views)
    end

    # The mean of the exact per-day uniques. Labelled as a daily average
    # wherever it is printed, because summing daily uniques into a "period
    # visitors" figure would count a returning reader once per visit.
    def average_daily_visitors : Float64
      daily.sum(0_i64, &.visitors).to_f / days
    end

    def busiest_day : DayCount?
      daily.max_by?(&.views)
    end
  end

  # The period parameter, constrained to the offered set. Anything
  # unrecognised is the default: a garbage value must not become a 500 or,
  # worse, an unbounded window.
  def self.period_days(param : String?) : Int32
    days = param.try(&.to_i?)
    PERIODS.includes?(days) ? days.not_nil! : DEFAULT_PERIOD
  end

  def self.build(days : Int32, content_kinds : Array(String), list_size : Int32 = 10) : Report
    to = today
    from = to - (days - 1).days

    counting = rollup_state("daily_stats")
    first = first_counted_day

    Report.new(
      days: days,
      from: from,
      to: to,
      daily: daily_totals(from, to),
      top_pages: top_paths(content_kinds, from, to, list_size),
      referrers: top_referrers(from, to, list_size),
      direct_views: direct_views(from, to),
      countries: top_countries(from, to, list_size),
      search_console: search_console(from, to, list_size),
      first_counted_day: first,
      counted_through: counting.try(&.[0]) || last_counted_day,
      counting_error: !counting.nil? && !counting[1].nil?,
      # Only asked when the rollup has produced nothing: on every other
      # render the answer is not used, and the collector's table is the
      # largest one here.
      recording_since: first.nil? ? recording_since : nil
    )
  end

  # The exact daily series for the chart, read from the 'site' totals rows
  # only and zero-filled across the window. Never a SUM over grain rows:
  # their visitors columns cannot be added into a count of people.
  def self.daily_totals(from : Time, to : Time) : Array(DayCount)
    sql = <<-SQL
      SELECT day, views, visitors
      FROM daily_stats
      WHERE path_kind = 'site'
        AND day BETWEEN $1::date AND $2::date
      SQL

    by_day = Hash(Time, DayCount).new
    AppDatabase.query_each(sql, date_arg(from), date_arg(to), queryable: "StatsReport") do |rs|
      day = rs.read(Time)
      by_day[day] = DayCount.new(day, rs.read(Int64), rs.read(Int64))
    end

    # Zero-fill so the chart draws a flat line for quiet days rather than
    # skipping them, which would read as missing data.
    (0...days_between(from, to)).map do |offset|
      day = from + offset.days
      by_day[day]? || DayCount.new(day, 0_i64, 0_i64)
    end
  end

  # The most viewed paths of the given kinds, views exact, visitors a sum of
  # daily uniques (see the module comment). Ties break on path so the list is
  # stable between reloads.
  def self.top_paths(kinds : Array(String), from : Time, to : Time, limit : Int32) : Array(PageCount)
    sql = <<-SQL
      SELECT path, SUM(views)::bigint, SUM(visitors)::bigint
      FROM daily_stats
      WHERE path_kind = ANY($1)
        AND day BETWEEN $2::date AND $3::date
      GROUP BY path
      ORDER BY SUM(views) DESC, path ASC
      LIMIT $4
      SQL

    rows = [] of PageCount
    AppDatabase.query_each(sql, kinds, date_arg(from), date_arg(to), limit, queryable: "StatsReport") do |rs|
      rows << PageCount.new(rs.read(String), rs.read(Int64), rs.read(Int64))
    end
    rows
  end

  # Where readers came from, excluding 'direct'. Views are exact; visitors
  # the same sum-of-daily-uniques the top paths carry.
  def self.top_referrers(from : Time, to : Time, limit : Int32) : Array(ReferrerCount)
    sql = <<-SQL
      SELECT referrer_host, SUM(views)::bigint, SUM(visitors)::bigint
      FROM daily_stats
      WHERE referrer_host <> ''
        AND referrer_host <> 'direct'
        AND day BETWEEN $1::date AND $2::date
      GROUP BY referrer_host
      ORDER BY SUM(views) DESC, referrer_host ASC
      LIMIT $3
      SQL

    rows = [] of ReferrerCount
    AppDatabase.query_each(sql, date_arg(from), date_arg(to), limit, queryable: "StatsReport") do |rs|
      rows << ReferrerCount.new(rs.read(String), rs.read(Int64), rs.read(Int64))
    end
    rows
  end

  # The direct half of the referrers section, as a view count. Exact, because
  # views is additive.
  def self.direct_views(from : Time, to : Time) : Int64
    sql = <<-SQL
      SELECT COALESCE(SUM(views), 0)::bigint
      FROM daily_stats
      WHERE referrer_host = 'direct'
        AND day BETWEEN $1::date AND $2::date
      SQL

    AppDatabase.scalar(sql, date_arg(from), date_arg(to), queryable: "StatsReport").as(Int64)
  end

  # The small reach breakdown. 'unknown' rows are kept and labelled by the
  # page: dropping them would overstate how much of the audience the geo
  # header resolved.
  def self.top_countries(from : Time, to : Time, limit : Int32) : Array(CountryCount)
    sql = <<-SQL
      SELECT country, SUM(views)::bigint, SUM(visitors)::bigint
      FROM daily_stats
      WHERE country <> ''
        AND day BETWEEN $1::date AND $2::date
      GROUP BY country
      ORDER BY SUM(views) DESC, country ASC
      LIMIT $3
      SQL

    rows = [] of CountryCount
    AppDatabase.query_each(sql, date_arg(from), date_arg(to), limit, queryable: "StatsReport") do |rs|
      rows << CountryCount.new(rs.read(String), rs.read(Int64), rs.read(Int64))
    end
    rows
  end

  # The Search Console half of "where they came from", pre-digested into the
  # states the page renders. `queries` is empty both when Google reports a
  # true zero and when nothing has been fetched; `covered_through` and
  # `last_error` are what tell those apart, never the row count.
  def self.search_console(from : Time, to : Time, limit : Int32) : SearchConsole
    # Present and nonblank, the same test the fetch client applies. A blank
    # value is treated as absent rather than as a misconfigured property name.
    configured = !ENV["SEARCH_CONSOLE_PROPERTY"]?.blank?

    covered_through : Time? = nil
    last_error : String? = nil
    if configured
      state = rollup_state("search_console")
      covered_through = state.try(&.[0])
      last_error = state.try(&.[1])
    end

    queries = configured ? top_queries(from, to, limit) : [] of QueryCount
    SearchConsole.new(configured, covered_through, last_error, queries)
  end

  # Google's top queries by clicks. Position is the impressions-weighted mean
  # (see QueryCount). Pages are not listed: the page shows what people
  # searched for, and the per-page half would duplicate the most-read list.
  def self.top_queries(from : Time, to : Time, limit : Int32) : Array(QueryCount)
    sql = <<-SQL
      SELECT query,
             SUM(clicks)::bigint,
             SUM(impressions)::bigint,
             COALESCE(SUM(position * impressions) / NULLIF(SUM(impressions), 0), 0)
      FROM search_console_daily
      WHERE day BETWEEN $1::date AND $2::date
      GROUP BY query
      ORDER BY SUM(clicks) DESC, SUM(impressions) DESC, query ASC
      LIMIT $3
      SQL

    rows = [] of QueryCount
    AppDatabase.query_each(sql, date_arg(from), date_arg(to), limit, queryable: "StatsReport") do |rs|
      rows << QueryCount.new(rs.read(String), rs.read(Int64), rs.read(Int64), rs.read(Float64))
    end
    rows
  end

  # The first day this site ever counted, from the totals rows.
  def self.first_counted_day : Time?
    sql = "SELECT MIN(day) FROM daily_stats WHERE path_kind = 'site'"
    AppDatabase.scalar(sql, queryable: "StatsReport").as(Time?)
  end

  # When the collector's own table first holds a row. Asked only when no day
  # has rolled, which is the one state where the difference between "nothing
  # recorded" and "nothing rolled yet" is visible to a reader. Indexed on
  # occurred_at, and the table is pruned, so this is a bounded index scan.
  def self.recording_since : Time?
    sql = "SELECT MIN(occurred_at) FROM page_views"
    AppDatabase.scalar(sql, queryable: "StatsReport").as(Time?)
  end

  # The newest day present in the totals rows, used as the coverage marker
  # only when the claim row is absent (a deploy before the rollup service
  # first runs).
  def self.last_counted_day : Time?
    sql = "SELECT MAX(day) FROM daily_stats WHERE path_kind = 'site'"
    AppDatabase.scalar(sql, queryable: "StatsReport").as(Time?)
  end

  # One claim row as {covered_through, last_error}, or nil when absent.
  private def self.rollup_state(name : String) : {Time?, String?}?
    sql = "SELECT covered_through, last_error FROM stats_rollups WHERE name = $1"
    AppDatabase.query_one?(sql, name, as: {Time?, String?}, queryable: "StatsReport")
  end

  # The window's end anchor. UTC, because the collector stamps days in UTC and
  # a site-local date would put the boundary an unpredictable distance from
  # the data's.
  private def self.today : Time
    now = Time.utc
    Time.utc(now.year, now.month, now.day)
  end

  # Dates go to Postgres as ISO text with an explicit ::date cast at the call
  # site, which is unambiguous for every parameter type inference path.
  private def self.date_arg(time : Time) : String
    time.to_s("%Y-%m-%d")
  end

  private def self.days_between(from : Time, to : Time) : Int32
    ((to - from).total_days.to_i + 1)
  end
end
