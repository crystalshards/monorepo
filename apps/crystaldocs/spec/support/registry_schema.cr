# The registry's tables, so the hand written SQL in `RegistryMetadata` can be
# run rather than stubbed.
#
# `RegistryMetadata` is three statements against another app's schema, and the
# defect they carried was a key mismatch: they matched `shards.name` while
# every caller passes `docs.package_name`, which for anything the registry
# indexed is a canonical slug. That is invisible to a fake registry, because a
# fake ignores the key it is asked for, which is exactly why the suite had
# nothing to say while every cross package link on the site was plain text.
#
# The tables are created in this app's own test database rather than in
# crystalshards'. The crystaldocs CI job never creates that database, and
# where it does exist a concurrent crystalshards run truncates it between
# examples, so either way it cannot carry an assertion. This app's test
# database is already unique to this suite, and its schema uses none of these
# three names.
#
# The columns are only the ones the statements read. A mirror of the registry's
# full schema would have to be maintained against another app's migrations,
# which is the coupling `RegistryMetadata` documents as the reason it is SQL
# and not models.
class RegistrySchema
  DDL = [
    <<-SQL,
      CREATE TABLE IF NOT EXISTS shards (
        id bigserial PRIMARY KEY,
        name text NOT NULL,
        canonical_slug text UNIQUE
      )
      SQL
    <<-SQL,
      CREATE TABLE IF NOT EXISTS shard_versions (
        id bigserial PRIMARY KEY,
        shard_id bigint NOT NULL,
        version text NOT NULL,
        crystal_version text,
        yanked boolean NOT NULL DEFAULT false
      )
      SQL
    <<-SQL,
      CREATE TABLE IF NOT EXISTS dependencies (
        id bigserial PRIMARY KEY,
        shard_version_id bigint NOT NULL,
        dependent_shard_id bigint,
        name text NOT NULL,
        version_requirement text NOT NULL,
        scope text NOT NULL DEFAULT 'runtime'
      )
      SQL
  ]

  @@created = false

  # Empty tables, ready to be seeded.
  #
  # Truncated here rather than left to the suite's own cleaner: that one reads
  # the table list once, and these tables are created after it has looked.
  def self.reset
    unless @@created
      DDL.each { |statement| RegistryDatabase.exec(statement) }
      @@created = true
    end

    RegistryDatabase.exec(
      "TRUNCATE TABLE dependencies, shard_versions, shards RESTART IDENTITY"
    )
  end

  # A repository, as the registry records one. `slug` is nullable for the same
  # reason the column is: rows predating host qualified identity have none.
  def self.shard(name : String, slug : String? = nil) : Int64
    RegistryDatabase.query_one(
      "INSERT INTO shards (name, canonical_slug) VALUES ($1, $2) RETURNING id",
      name,
      slug,
      as: Int64
    )
  end

  # A published release. `crystal` is the `crystal:` key copied out of
  # shard.yml, which is a requirement rather than a version.
  def self.version(
    shard_id : Int64,
    version : String,
    crystal : String? = nil,
    yanked : Bool = false,
  ) : Int64
    RegistryDatabase.query_one(
      <<-SQL,
        INSERT INTO shard_versions (shard_id, version, crystal_version, yanked)
        VALUES ($1, $2, $3, $4)
        RETURNING id
        SQL
      shard_id,
      version,
      crystal,
      yanked,
      as: Int64
    )
  end

  # A dependency the release declared. `resolved_shard_id` is nil when the
  # registry could not match the shard.yml key to a repository it holds, which
  # is a real state and the one that decides whether a link is possible.
  def self.dependency(
    shard_version_id : Int64,
    name : String,
    requirement : String,
    resolved_shard_id : Int64? = nil,
    scope : String = "runtime",
  )
    RegistryDatabase.exec(
      <<-SQL,
        INSERT INTO dependencies
          (shard_version_id, dependent_shard_id, name, version_requirement, scope)
        VALUES ($1, $2, $3, $4, $5)
        SQL
      shard_version_id,
      resolved_shard_id,
      name,
      requirement,
      scope
    )
  end
end

# Point the registry connection at this suite's own database.
#
# Done at load time, before any example runs and therefore before anything has
# opened a registry connection, so the pool is built against these credentials
# rather than rebuilt underneath one.
#
# This also removes a quieter problem. Configured but pointing at a database
# that does not exist, which is what the crystaldocs CI job produces, every
# registry read raises and is swallowed by a rescue, so examples pass through
# an error path that looks like an answer.
RegistryDatabase.configure do |settings|
  settings.credentials = AppDatabase.credentials
end

RegistryDatabase.configured = true
