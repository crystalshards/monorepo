# Planting helpers for the stats specs. The tables are written by three other
# services (collector, rollup, Search Console client), so specs plant their
# output verbatim with raw INSERTs rather than reaching for factories that
# belong to those services.

# Midnight UTC on the day `n` days before today, matching the date grain the
# rollup writes.
def days_ago(n : Int) : Time
  today = Time.utc
  Time.utc(today.year, today.month, today.day) - n.days
end

# One 'site' totals row: the exact per-day figures the chart reads.
def plant_site_day(day : Time, views : Int64, visitors : Int64)
  AppDatabase.run do |db|
    db.exec <<-SQL, day.to_s("%Y-%m-%d"), views, visitors
      INSERT INTO daily_stats (day, path_kind, path, referrer_host, country, views, visitors)
      VALUES ($1::date, 'site', '', '', '', $2, $3)
      SQL
  end
end

# One full-grain row, the shape every per-path, per-referrer and per-country
# list is summed out of.
def plant_grain(day : Time, kind : String, path : String, referrer : String, country : String, views : Int64, visitors : Int64)
  AppDatabase.run do |db|
    db.exec <<-SQL, day.to_s("%Y-%m-%d"), kind, path, referrer, country, views, visitors
      INSERT INTO daily_stats (day, path_kind, path, referrer_host, country, views, visitors)
      VALUES ($1::date, $2, $3, $4, $5, $6, $7)
      SQL
  end
end

def plant_query(day : Time, query : String, page : String, clicks : Int64, impressions : Int64, position : Float64)
  AppDatabase.run do |db|
    db.exec <<-SQL, day.to_s("%Y-%m-%d"), query, page, clicks, impressions, position
      INSERT INTO search_console_daily (day, query, page, clicks, impressions, position)
      VALUES ($1::date, $2, $3, $4, $5, $6)
      SQL
  end
end

# A claim row: the marker that a pipeline has settled every day through
# `covered_through`, or that its last run failed with `last_error`.
def plant_rollup(name : String, covered_through : Time? = nil, last_error : String? = nil)
  AppDatabase.run do |db|
    db.exec <<-SQL, name, covered_through.try(&.to_s("%Y-%m-%d")), last_error
      INSERT INTO stats_rollups (name, covered_through, last_error)
      VALUES ($1, $2::date, $3)
      SQL
  end
end

# SEARCH_CONSOLE_PROPERTY is the configured signal the fetch client keys on;
# specs set it per example and never leak it into the next one.
def with_search_console_property(&)
  ENV["SEARCH_CONSOLE_PROPERTY"] = "sc-domain:crystalbits.org"
  yield
ensure
  ENV.delete("SEARCH_CONSOLE_PROPERTY")
end

# How many day rows the chart's text-equivalent table carries. Dates only
# ever appear in that table's first column, so counting date cells counts
# window days without coupling to table markup.
def chart_days(body : String) : Int32
  body.scan(/<td>[A-Z][a-z]{2} \d{1,2}, \d{4}<\/td>/).size
end
