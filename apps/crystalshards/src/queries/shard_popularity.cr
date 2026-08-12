# Popularity for a registry that serves no packages.
#
# Nothing is downloaded from here. `shards` resolves a dependency and fetches
# it from the origin repository, so a download counter on this side can only
# ever read zero. The two signals that can actually be populated are stars,
# which come from the host's repo metadata, and dependents, which we compute
# from our own dependency edges.
#
# The two are not symmetric, and the UI has to say so:
#
#   Stars are fetched from a third party, so they can be genuinely UNKNOWN.
#   `shards.github_stars` is nil when no successful metadata fetch has
#   happened yet, and the indexer never writes 0 as a placeholder. nil means
#   "not indexed", 0 means "fetched, and nobody has starred it".
#
#   Dependents are derived from tables we own, so they are never unknown.
#   A shard nothing depends on has zero dependents, and that is a fact rather
#   than a gap.
#
# EDGE DIRECTION. `dependencies.dependent_shard_id` reads backwards from what
# it does: it is the shard being depended ON, resolved by
# UpdateDependenciesWorker#resolve_dependent_shard from a shard.yml entry. The
# shard doing the depending is reached through
# `dependencies.shard_version_id -> shard_versions.shard_id`.
#
# Two consequences every query here has to honour:
#
#   COUNT(DISTINCT shard_versions.shard_id), never COUNT(*). The worker writes
#   one edge per VERSION, so a depender with eight releases would otherwise be
#   counted eight times.
#
#   sv.shard_id <> d.dependent_shard_id. "How many OTHER shards depend on this"
#   excludes the shard's own dev_dependency on itself, which is a common
#   self-hosting pattern and is not a dependent.
#
# Unresolved edges carry a null dependent_shard_id and are excluded for free by
# the equality test: a requirement on a shard we cannot identify is recorded,
# but it does not count as a dependent of anything.
module ShardPopularity
  # The dependents half of the ORDER BY for the default listing.
  #
  # This is a correlated subquery rather than a join so that it composes with
  # the filters ShardQuery already builds (search, license, min stars, docs)
  # and with LIMIT/OFFSET, without any of them needing to know it exists. It
  # stays one statement, so a listing page does not gain a query by ordering
  # this way. Avram's `select_count` calls `reset_order`, so the COUNT(*) that
  # drives pagination never carries this clause.
  class DependentsOrder < Avram::OrderByClause
    def_clone

    EXPRESSION = <<-SQL.squeeze(" ").gsub("\n", " ").strip
      (SELECT COUNT(DISTINCT sv.shard_id)
       FROM dependencies d
       JOIN shard_versions sv ON sv.id = d.shard_version_id
       WHERE d.dependent_shard_id = shards.id
         AND sv.shard_id <> shards.id)
      SQL

    getter column : String | Symbol = EXPRESSION
    getter direction : Avram::OrderBy::Direction

    def initialize(@direction : Avram::OrderBy::Direction = :desc)
    end

    def prepare : String
      "#{EXPRESSION} #{direction}"
    end

    def reversed : self
      @direction = @direction.asc? ? Avram::OrderBy::Direction::DESC : Avram::OrderBy::Direction::ASC
      self
    end
  end

  # How many other indexed shards declare a dependency on this one.
  def self.dependent_count(shard_id : Int64) : Int32
    sql = <<-SQL
      SELECT COUNT(DISTINCT sv.shard_id)
      FROM dependencies d
      JOIN shard_versions sv ON sv.id = d.shard_version_id
      WHERE d.dependent_shard_id = $1
        AND sv.shard_id <> $1
      SQL

    AppDatabase.scalar(sql, shard_id, queryable: "ShardPopularity").as(Int64).to_i32
  end

  # The same count for a whole page of shards in one query.
  #
  # A listing mounts one card per shard and every card shows a dependent
  # count, so asking per card would be an N+1 that grows with page size. The
  # action resolves the page's ids once and hands the cards a lookup.
  #
  # Shards with no dependents are absent from the GROUP BY and are filled in
  # as 0, so callers can index the hash for any id they asked about.
  def self.dependent_counts(shard_ids : Array(Int64)) : Hash(Int64, Int32)
    counts = Hash(Int64, Int32).new
    return counts if shard_ids.empty?

    shard_ids.each { |id| counts[id] = 0 }
    sql = <<-SQL
      SELECT d.dependent_shard_id, COUNT(DISTINCT sv.shard_id)
      FROM dependencies d
      JOIN shard_versions sv ON sv.id = d.shard_version_id
      WHERE d.dependent_shard_id = ANY($1)
        AND sv.shard_id <> d.dependent_shard_id
      GROUP BY d.dependent_shard_id
      SQL

    AppDatabase.query_each(sql, shard_ids, queryable: "ShardPopularity") do |rs|
      id = rs.read(Int64)
      counts[id] = rs.read(Int64).to_i32
    end

    counts
  end

  # The shards that depend on this one, most recently released first.
  #
  # Returns ids, not shards: the caller loads them in one query and re-sorts to
  # this order, because an IN query does not preserve it. A count with no way
  # to see what is behind it is the dead end this whole change is fixing, so
  # the show page lists them.
  def self.dependent_ids(shard_id : Int64, limit : Int32 = 12) : Array(Int64)
    sql = <<-SQL
      SELECT sv.shard_id
      FROM dependencies d
      JOIN shard_versions sv ON sv.id = d.shard_version_id
      WHERE d.dependent_shard_id = $1
        AND sv.shard_id <> $1
      GROUP BY sv.shard_id
      ORDER BY MAX(sv.released_at) DESC NULLS LAST
      LIMIT $2
      SQL

    AppDatabase.query_all(sql, shard_id, limit, as: Int64, queryable: "ShardPopularity")
  end

  # The homepage star stat, as a pair: how many shards have a star count at
  # all, and what those counts sum to.
  #
  # Returning both is the whole point. A sum on its own cannot distinguish
  # "we measured every shard and nobody has starred them" from "we have not
  # fetched metadata yet", and printing a confident 0 for the second is the
  # exact failure that made the download counter worth deleting. COUNT of a
  # nullable column counts non-nulls, so the first number is star coverage.
  def self.star_totals : {Int32, Int64}
    sql = <<-SQL
      SELECT COUNT(github_stars), COALESCE(SUM(github_stars), 0)
      FROM shards
      SQL

    counted, summed = AppDatabase.query_one(sql, as: {Int64, Int64}, queryable: "ShardPopularity")

    {counted.to_i32, summed}
  end

  # The homepage dependents stat: how many distinct shard-to-shard dependency
  # links the registry has resolved.
  #
  # A link is a (depender, target) pair, counted once no matter how many
  # versions or scopes declare it, which is the same DISTINCT rule
  # `dependent_counts` applies per shard. This is deliberately NOT a count of
  # `dependencies` rows: that number is inflated by every release and would
  # overstate how connected the ecosystem is.
  #
  # Unlike stars this needs no coverage companion. It is computed from tables
  # we own, so zero links is a measured fact, not a gap.
  def self.dependency_link_total : Int64
    sql = <<-SQL
      SELECT COUNT(*)
      FROM (
        SELECT DISTINCT sv.shard_id, d.dependent_shard_id
        FROM dependencies d
        JOIN shard_versions sv ON sv.id = d.shard_version_id
        WHERE d.dependent_shard_id IS NOT NULL
          AND sv.shard_id <> d.dependent_shard_id
      ) links
      SQL

    AppDatabase.scalar(sql, queryable: "ShardPopularity").as(Int64)
  end
end
