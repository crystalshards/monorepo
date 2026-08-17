# The four stats tables, created for the spec suite only.
#
# Their migrations belong to sibling branches that are being integrated with
# this one: the collector ships page_views and stats_rollups, the rollup
# service ships daily_stats, the Search Console client ships
# search_console_daily. This app ships no migration for them, so an
# integration never resolves two copies of one table.
#
# The suite cannot wait on those branches: the specs below plant rows in
# these tables. Every statement is IF NOT EXISTS against the shared
# contract's DDL, so once the real migrations have run this file is a no-op,
# and a spec run against a migrated database tests the real schema.
AppDatabase.run do |db|
  db.exec <<-SQL
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
  db.exec "CREATE INDEX IF NOT EXISTS page_views_occurred_at_index ON page_views (occurred_at)"

  db.exec <<-SQL
    CREATE TABLE IF NOT EXISTS stats_rollups (
      id bigserial PRIMARY KEY,
      name text NOT NULL,
      covered_through date,
      claimed_at timestamptz,
      last_error text
    )
    SQL
  db.exec "CREATE UNIQUE INDEX IF NOT EXISTS stats_rollups_name_index ON stats_rollups (name)"

  db.exec <<-SQL
    CREATE TABLE IF NOT EXISTS daily_stats (
      id bigserial PRIMARY KEY,
      day date NOT NULL,
      path_kind text NOT NULL,
      path text NOT NULL,
      referrer_host text NOT NULL,
      country text NOT NULL,
      views bigint NOT NULL,
      visitors bigint NOT NULL
    )
    SQL
  db.exec "CREATE UNIQUE INDEX IF NOT EXISTS daily_stats_day_path_kind_path_referrer_host_country_index ON daily_stats (day, path_kind, path, referrer_host, country)"

  db.exec <<-SQL
    CREATE TABLE IF NOT EXISTS search_console_daily (
      id bigserial PRIMARY KEY,
      day date NOT NULL,
      query text NOT NULL,
      page text NOT NULL,
      clicks bigint NOT NULL,
      impressions bigint NOT NULL,
      position float8 NOT NULL
    )
    SQL
  db.exec "CREATE UNIQUE INDEX IF NOT EXISTS search_console_daily_day_query_page_index ON search_console_daily (day, query, page)"
end

# Avram's between-specs cleaner only truncates tables a registered model
# claims, and in this worktree no model claims these four. Without this hook
# a row planted by one spec would leak into the next one's empty state.
# Once the owning branches integrate, their models make this a redundant
# second delete, which is the safe direction for a cleanup to drift.
Spec.before_each do
  AppDatabase.run do |db|
    db.exec "DELETE FROM search_console_daily"
    db.exec "DELETE FROM daily_stats"
    db.exec "DELETE FROM stats_rollups"
    db.exec "DELETE FROM page_views"
  end
end
