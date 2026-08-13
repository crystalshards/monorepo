module CrystalDocs
  # Reads the two pieces of dependency metadata this app does not own.
  #
  # crystaldocs knows which artifacts it has built. It does not know what any
  # of them declared, and the declaration is the whole question when deciding
  # where a cross package link should point. Both answers live in the registry
  # that crystalshards writes:
  #
  #   * `dependencies.version_requirement`, per shard version, which is the
  #     requirement that version of that shard actually asked for.
  #   * `shard_versions.crystal_version`, which is the `crystal:` key copied
  #     verbatim out of shard.yml. Despite the column name it holds a
  #     requirement, not a version: ">= 1.0.0" and "1.0.0" are both real
  #     values in this system.
  #
  # The boundary is crossed with a second read only connection, configured as
  # `RegistryDatabase`, rather than by copying rows into this app's schema. One
  # writer, no copy to fall behind. The cost is a dependency on another app's
  # tables, so the queries are hand written SQL over a handful of columns
  # instead of Avram models mirrored from crystalshards: a model would drag in
  # schema enforcement and break this app's boot whenever the registry added a
  # column, which is not a failure crystaldocs should be able to have.
  class RegistryMetadata
    # A dependency of the source version, addressed by the key this app
    # documents it under rather than by the name shard.yml wrote.
    record DeclaredDependency, key : String, requirement : String

    # What one published version of one shard declared.
    record SourceVersion,
      crystal_requirement : String?,
      dependencies : Array(DeclaredDependency)

    # A candidate to link to: published, not yanked, with whatever Crystal
    # support it declared.
    record PublishedVersion, version : String, crystal_requirement : String?

    # Test seam, mirroring the pattern the rest of the services use.
    class_property provider : Proc(RegistryMetadata)? = nil

    def self.build : RegistryMetadata
      if custom = @@provider
        custom.call
      else
        new
      end
    end

    # Everything here is addressed by `docs.package_name`, which is the key
    # this app documents a package under, and never by a bare shard name on
    # its own. `PackagePaths` describes the two shapes it takes: a canonical
    # slug ("github.com/kemalcr/kemal"), which every row created from the
    # registry carries, and a bare name ("crystal", "kemal"), which belongs to
    # the standard library and to the rows predating host qualified identity.
    #
    # Matching `shards.name` alone is what made every cross package link on
    # this site plain text. A slug matched no row, `source` answered nil, and
    # `DependencyIndex` returned an empty index at its first guard, so neither
    # a dependency name nor a standard library name could resolve.
    #
    # `shards.canonical_slug` carries a unique index and `shards.name` does
    # not, so a bare name can name several repositories. That is reported as
    # ambiguity rather than settled by taking the first row: a link into a
    # different repository's API is worse than no link.
    #
    # `shard_id` is selected alongside the requirement so the row has a column
    # that is never NULL. Reading only `crystal_version` makes "no such
    # published version" and "published, declared no Crystal" arrive as the
    # same nil, and those are different answers. It is also what the
    # dependency query is then keyed on, so the key is resolved to a
    # repository exactly once.
    SHARD_VERSION_SQL = <<-SQL
      WITH matched AS (
        SELECT shards.id
        FROM shards
        WHERE shards.canonical_slug = $1 OR shards.name = $1
      )
      SELECT shard_versions.shard_id,
             shard_versions.crystal_version,
             (SELECT count(*) FROM matched)
      FROM shard_versions
      WHERE shard_versions.shard_id IN (SELECT id FROM matched)
        AND shard_versions.version = $2
      SQL

    # Development dependencies are excluded. A published API can only mention
    # types from what it links against at runtime, so a spec helper or a linter
    # in the dependency list is not a source of names a reader will meet.
    #
    # The key returned is the one this app would document the dependency
    # under, which is the resolved shard's `canonical_slug` whenever the
    # registry managed to resolve one. That is the whole reason this reads
    # `canonical_slug` first: the registry records a dependency by the name
    # shard.yml wrote, and this app's rows are keyed by slug, so returning the
    # name would ask the index to join two different naming schemes and find
    # nothing.
    #
    # The raw shard.yml key is the last fallback, and it only ever produces a
    # link if some row happens to be documented under exactly it. The registry
    # declining to resolve a dependency is not licence to resolve it here.
    DEPENDENCIES_SQL = <<-SQL
      SELECT
        COALESCE(
          dependent_shards.canonical_slug,
          dependent_shards.name,
          dependencies.name
        ),
        dependencies.version_requirement
      FROM dependencies
      JOIN shard_versions ON shard_versions.id = dependencies.shard_version_id
      LEFT JOIN shards AS dependent_shards
        ON dependent_shards.id = dependencies.dependent_shard_id
      WHERE shard_versions.shard_id = $1
        AND shard_versions.version = $2
        AND dependencies.scope = 'runtime'
      SQL

    # Answered in the same key shape it is asked in, so a caller never has to
    # translate between what the registry calls a shard and what this app
    # documents it as. A name is only matched for rows that have no slug at
    # all, because a slug is unique and a name is not.
    PUBLISHED_VERSIONS_SQL = <<-SQL
      SELECT COALESCE(shards.canonical_slug, shards.name),
             shard_versions.version,
             shard_versions.crystal_version
      FROM shard_versions
      JOIN shards ON shards.id = shard_versions.shard_id
      WHERE (
          shards.canonical_slug = ANY($1)
          OR (shards.canonical_slug IS NULL AND shards.name = ANY($1))
        )
        AND shard_versions.yanked = false
      SQL

    # Returns nil when the registry has no such published version, which is a
    # different answer from a version that declared nothing.
    #
    # Also nil when the key names more than one repository, because then which
    # of them published this version, and what it declared, has no single
    # answer.
    #
    # Also nil when no registry is configured at all. An environment without
    # one has unknown constraints rather than permissive ones, and unknown
    # already resolves to plain text.
    def source(package_name : String, version : String) : SourceVersion?
      return nil unless RegistryDatabase.configured?

      rows = RegistryDatabase.query_all(
        SHARD_VERSION_SQL,
        package_name,
        version,
        as: {Int64, String?, Int64}
      )

      row = rows.first?
      return nil unless row
      return nil unless row[2] == 1

      declared = RegistryDatabase.query_all(
        DEPENDENCIES_SQL,
        row[0],
        version,
        as: {String, String}
      ).map { |(key, requirement)| DeclaredDependency.new(key, requirement) }

      SourceVersion.new(row[1], declared)
    end

    # Every non yanked published version of each named package, in one round
    # trip. Yanked versions are left out because a link is a recommendation,
    # and the registry has already said not to use those.
    def published_versions(package_keys : Array(String)) : Hash(String, Array(PublishedVersion))
      published = {} of String => Array(PublishedVersion)
      return published unless RegistryDatabase.configured?
      return published if package_keys.empty?

      rows = RegistryDatabase.query_all(
        PUBLISHED_VERSIONS_SQL,
        package_keys,
        as: {String, String, String?}
      )

      rows.each do |(key, version, crystal_requirement)|
        versions = published[key] ||= [] of PublishedVersion
        versions << PublishedVersion.new(version, crystal_requirement)
      end

      published
    end
  end
end
