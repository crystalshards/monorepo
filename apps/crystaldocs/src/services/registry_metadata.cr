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
    # A dependency exactly as the source version declared it.
    record DeclaredDependency, name : String, requirement : String

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

    # The version column is selected alongside the requirement purely so the
    # row has a column that is never NULL. Reading only `crystal_version`
    # makes "no such published version" and "published, declared no Crystal"
    # arrive as the same nil, and those are different answers.
    CRYSTAL_REQUIREMENT_SQL = <<-SQL
      SELECT shard_versions.version, shard_versions.crystal_version
      FROM shard_versions
      JOIN shards ON shards.id = shard_versions.shard_id
      WHERE shards.name = $1
        AND shard_versions.version = $2
      LIMIT 1
      SQL

    # Development dependencies are excluded. A published API can only mention
    # types from what it links against at runtime, so a spec helper or a linter
    # in the dependency list is not a source of names a reader will meet.
    #
    # The name is taken from the shard the registry resolved the dependency to
    # when it managed to resolve one, because that is the name this site
    # publishes documentation under. The raw shard.yml key is the fallback.
    DEPENDENCIES_SQL = <<-SQL
      SELECT
        COALESCE(dependent_shards.name, dependencies.name),
        dependencies.version_requirement
      FROM dependencies
      JOIN shard_versions ON shard_versions.id = dependencies.shard_version_id
      JOIN shards ON shards.id = shard_versions.shard_id
      LEFT JOIN shards AS dependent_shards
        ON dependent_shards.id = dependencies.dependent_shard_id
      WHERE shards.name = $1
        AND shard_versions.version = $2
        AND dependencies.scope = 'runtime'
      SQL

    # Returns nil when the registry has no such published version, which is a
    # different answer from a version that declared nothing.
    #
    # Also nil when no registry is configured at all. An environment without
    # one has unknown constraints rather than permissive ones, and unknown
    # already resolves to plain text.
    def source(package_name : String, version : String) : SourceVersion?
      return nil unless RegistryDatabase.configured?

      rows = RegistryDatabase.query_all(
        CRYSTAL_REQUIREMENT_SQL,
        package_name,
        version,
        as: {String, String?}
      )

      row = rows.first?
      return nil unless row

      declared = RegistryDatabase.query_all(
        DEPENDENCIES_SQL,
        package_name,
        version,
        as: {String, String}
      ).map { |(name, requirement)| DeclaredDependency.new(name, requirement) }

      SourceVersion.new(row[1], declared)
    end

    # Every non yanked published version of each named shard, in one round
    # trip. Yanked versions are left out because a link is a recommendation,
    # and the registry has already said not to use those.
    def published_versions(package_names : Array(String)) : Hash(String, Array(PublishedVersion))
      published = {} of String => Array(PublishedVersion)
      return published unless RegistryDatabase.configured?
      return published if package_names.empty?

      # Placeholders are generated from the count, never from the names, so
      # the names stay bound parameters.
      placeholders = (1..package_names.size).join(", ") { |position| "$#{position}" }

      sql = <<-SQL
        SELECT shards.name, shard_versions.version, shard_versions.crystal_version
        FROM shard_versions
        JOIN shards ON shards.id = shard_versions.shard_id
        WHERE shards.name IN (#{placeholders})
          AND shard_versions.yanked = false
        SQL

      rows = RegistryDatabase.query_all(
        sql,
        args: package_names.map(&.as(DB::Any)),
        as: {String, String, String?}
      )

      rows.each do |(name, version, crystal_requirement)|
        versions = published[name] ||= [] of PublishedVersion
        versions << PublishedVersion.new(version, crystal_requirement)
      end

      published
    end
  end
end
