class CreateDailyStats::V00000000000007 < Avram::Migrator::Migration::V1
  # The permanent home for what the public stats page shows. Raw page_views
  # rows are pruned 30 days after they are written, so anything the page
  # says about older traffic has to live here, aggregated, before the raw
  # row goes away.
  #
  # One row per day per (path_kind, path, referrer_host, country), which is
  # the finest grain the page ever groups by. The unique index is not
  # decoration: the rollup recomputes a day from raw rows and upserts
  # against exactly this key, which is what makes re-rolling a day
  # idempotent after a failed pass. Write the rollup any other way and a
  # retry double counts.
  #
  # Raw SQL rather than the Avram DSL because the DSL has no date column
  # type (`add day : Time` would make a timestamptz), and a day that carries
  # a time zone is how off-by-one-day bugs happen. `day` is a real Postgres
  # date, always UTC, never today: a day is rolled only once it has fully
  # ended.
  #
  # referrer_host and country are NOT NULL here though page_views allows
  # NULL: the rollup coalesces to 'direct' and 'unknown' on the way in, so
  # the grain key never has to compare NULLs and the page never renders a
  # blank bucket.
  #
  # path_kind = 'site' rows (empty path, referrer_host and country) are the
  # one addition to the collector's closed kind set: they carry whole-day
  # totals whose visitors is an exact COUNT(DISTINCT visitor_hash) over the
  # day. Summing visitors across path rows counts a person who read two
  # pages twice, so the page's per-day totals come from these rows and
  # nowhere else. See CrystalBits::Stats.
  def migrate
    execute <<-SQL
      CREATE TABLE daily_stats (
        id BIGSERIAL PRIMARY KEY,
        day date NOT NULL,
        path_kind text NOT NULL,
        path text NOT NULL,
        referrer_host text NOT NULL,
        country text NOT NULL,
        views bigint NOT NULL,
        visitors bigint NOT NULL,
        created_at timestamptz NOT NULL DEFAULT NOW(),
        updated_at timestamptz NOT NULL DEFAULT NOW()
      )
      SQL

    execute <<-SQL
      CREATE UNIQUE INDEX daily_stats_grain_index
        ON daily_stats (day, path_kind, path, referrer_host, country)
      SQL
  end

  def rollback
    execute "DROP TABLE daily_stats"
  end
end
