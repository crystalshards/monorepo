class CreatePageViewsAndStatsRollups::V00000000000006 < Avram::Migrator::Migration::V1
  def migrate
    # One row per real page view, collected server side by PageViewHandler
    # and read by the daily rollup. Nothing on the row identifies a person:
    # visitor_hash is a salted digest (see PageViews.visitor_hash), the
    # referrer is a host rather than a URL, and no address or agent string is
    # ever stored. That is what makes this a count of readers without being a
    # record of them, and it is why the downloads table's raw ip_address
    # column is a mistake this table does not repeat.
    #
    # No created_at/updated_at, on this the highest-volume table the app
    # keeps: a row is written once, read by the rollup, and pruned, so the
    # only time that means anything is occurred_at. Avram's model default
    # would add both; the model skips it to match.
    create table_for(PageView) do
      primary_key id : Int64

      # The path only, never the query string: a search term is what a reader
      # typed, and the `search` path_kind already says a search happened.
      add path : String
      # One of a small closed set (home, browse, package, docs_version,
      # docs_type, search, job, post, api, other), so the rollup's groups do
      # not explode across every URL shape the sites have ever served.
      add path_kind : String
      # The host of the Referer, or NULL when there is none. The rollup folds
      # NULL into its 'direct' bucket, which is why daily_stats can keep the
      # column NOT NULL while this one stays honest about what was sent.
      add referrer_host : String?
      # The country the load balancer resolved, or NULL when it could not.
      # Never guessed from the address: a VPN reader counts as unknown, not
      # as a wrong country.
      add country : String?
      add visitor_hash : String
      add occurred_at : Time, index: true
    end

    # The claim row that makes a lazy rollup safe, created with raw SQL for
    # exactly one reason: covered_through is a real Postgres date, and
    # Avram's migration DSL has no date type. The pg driver decodes date as
    # Time at midnight, so anything reading it through a model declaring
    # `column covered_through : Time?` still works, and the schema enforcer
    # checks existence and nullability rather than the database type.
    #
    # The shape is the whole contract between the rollups that claim through
    # it: a name to claim under, how far coverage has reached, when a claim
    # was taken (so a dead claimant stops blocking work), and the last error
    # a claim ran into. Per the division of this feature, the collector owns
    # the table and nothing here writes to it yet; the rollup writes it from
    # its first read.
    execute <<-SQL
      CREATE TABLE stats_rollups (
        id bigserial PRIMARY KEY,
        name text NOT NULL UNIQUE,
        covered_through date,
        claimed_at timestamptz,
        last_error text
      )
      SQL
  end

  def rollback
    execute "DROP TABLE IF EXISTS stats_rollups"
    drop table_for(PageView)
  end
end
