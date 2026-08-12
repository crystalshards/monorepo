require "../app_database"

# Popularity, for a registry nothing is downloaded from.
#
# Packages are fetched from the origin repository by `shards`, never from us, so
# a download count here could only ever be zero and a permanent zero reads as
# "nobody uses this". The two signals that are real are stars, which the host
# reports, and dependents, which we can see in our own tables.
#
# A dependent is another shard that declares a dependency resolving to this
# one. The edge is stored on `dependencies` and the column names read
# backwards from the direction they point:
#
#   dependencies.dependent_shard_id                 the shard depended ON
#   dependencies.shard_version_id -> shard_id       the shard doing the depending
#
# Two rules apply to every count below and they are not optional.
# UpdateDependenciesWorker writes one edge per VERSION, so a depender with
# eight releases counts eight times unless the source shard is counted
# DISTINCT. And a development dependency on yourself is common, so a shard is
# excluded from its own dependents.
module ShardPopularity
  # How many other shards depend on this one.
  def self.dependent_count(shard_id : Int64) : Int32
    sql = <<-SQL
      SELECT COUNT(DISTINCT sv.shard_id)
      FROM dependencies d
      JOIN shard_versions sv ON sv.id = d.shard_version_id
      WHERE d.dependent_shard_id = $1 AND sv.shard_id <> $1
      SQL

    AppDatabase.run do |db|
      db.query_one(sql, shard_id, as: Int64).to_i32
    end
  end

  # The same count for many shards at once, for listings. Shards with no
  # dependents are absent from the result rather than present as zero, so
  # callers read it with a default.
  def self.dependent_counts(shard_ids : Array(Int64)) : Hash(Int64, Int32)
    counts = {} of Int64 => Int32
    return counts if shard_ids.empty?

    sql = <<-SQL
      SELECT d.dependent_shard_id, COUNT(DISTINCT sv.shard_id)
      FROM dependencies d
      JOIN shard_versions sv ON sv.id = d.shard_version_id
      WHERE d.dependent_shard_id = ANY($1) AND sv.shard_id <> d.dependent_shard_id
      GROUP BY d.dependent_shard_id
      SQL

    AppDatabase.run do |db|
      db.query_each(sql, shard_ids) do |rs|
        shard_id = rs.read(Int64)
        counts[shard_id] = rs.read(Int64).to_i32
      end
    end

    counts
  end

  # Which shards those are, most recently released first.
  #
  # A count with no way to see what it counts is the dead end this registry is
  # being dug out of, so the page lists them. Same WHERE clause and same
  # self-exclusion as dependent_count, so the list can never disagree with the
  # number above it.
  def self.dependent_ids(shard_id : Int64, limit : Int32 = 12) : Array(Int64)
    sql = <<-SQL
      SELECT sv.shard_id
      FROM dependencies d
      JOIN shard_versions sv ON sv.id = d.shard_version_id
      WHERE d.dependent_shard_id = $1 AND sv.shard_id <> $1
      GROUP BY sv.shard_id
      ORDER BY MAX(sv.released_at) DESC NULLS LAST
      LIMIT $2
      SQL
    AppDatabase.run do |db|
      db.query_all(sql, shard_id, limit, as: Int64)
    end
  end
end
