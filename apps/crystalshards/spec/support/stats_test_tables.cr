# The two tables the stats rollup reads but does not own.
#
# page_views and stats_rollups are created by the collector's migration in
# its own branch; until the branches integrate they do not exist in this
# worktree's test database, so the specs below create them here. This is
# the same discipline DocsTestDatabase sets for the docs tables: only the
# contract columns are defined, and CREATE TABLE IF NOT EXISTS is a no-op
# once the real migration has run, so an integrated checkout keeps working
# unchanged. The columns are the shared contract verbatim; a shape change
# there must be reflected here.
#
# The tables are created and truncated from the stats spec's own
# before_each rather than relying on the global clean_database hook:
# Avram's DatabaseCleaner discovers its table list once per process from a
# memoized database_info, which is loaded before these tables exist, so
# the global truncate never names them.
module StatsTestTables
  # One statement per element: the Postgres driver prepares every statement
  # it is given, and a prepared statement holds exactly one command.
  STATEMENTS = [
    <<-SQL,
    CREATE TABLE IF NOT EXISTS page_views (
      id bigserial PRIMARY KEY,
      path text NOT NULL,
      path_kind text NOT NULL,
      referrer_host text,
      country text,
      visitor_hash text NOT NULL,
      occurred_at timestamptz NOT NULL
    )
    SQL
    <<-SQL,
    CREATE INDEX IF NOT EXISTS page_views_occurred_at_index ON page_views (occurred_at)
    SQL
    <<-SQL,
    CREATE TABLE IF NOT EXISTS stats_rollups (
      id bigserial PRIMARY KEY,
      name text NOT NULL UNIQUE,
      covered_through date,
      claimed_at timestamptz,
      last_error text
    )
    SQL
  ]

  def self.prepare : Nil
    STATEMENTS.each { |statement| AppDatabase.exec(statement) }
  end

  def self.truncate : Nil
    AppDatabase.exec("TRUNCATE TABLE page_views, stats_rollups, daily_stats RESTART IDENTITY CASCADE")
  end
end

# Plants one raw view the way the collector writes it: visitor_hash already
# salted and hashed, referrer_host already reduced to a host, country
# already a two letter code or nil.
def plant_page_view(path : String, path_kind : String, occurred_at : Time, visitor : String = "visitor-1", referrer_host : String? = nil, country : String? = nil)
  AppDatabase.exec(
    "INSERT INTO page_views (path, path_kind, referrer_host, country, visitor_hash, occurred_at) VALUES ($1, $2, $3, $4, $5, $6)",
    path, path_kind, referrer_host, country, visitor, occurred_at
  )
end

# The UTC start of the day `days_ago` days before today, plus a margin so
# planted rows land squarely inside the intended day whatever time the
# suite runs at.
def stats_day(days_ago : Int32) : Time
  day = Time.utc - days_ago.days
  Time.utc(day.year, day.month, day.day) + 12.hours
end
