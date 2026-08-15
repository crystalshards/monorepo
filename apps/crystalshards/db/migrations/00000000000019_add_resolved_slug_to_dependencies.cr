class AddResolvedSlugToDependencies::V00000000000019 < Avram::Migrator::Migration::V1
  def migrate
    # The repository a dependency names, as a canonical slug.
    #
    # This was already being computed and thrown away. A shard.yml dependency
    # carries its own source:
    #
    #   router:
    #     gitlab: acme/router
    #
    # and UpdateDependenciesWorker already resolves that to
    # "gitlab.com/acme/router" in order to look up a shards row. When no row
    # answered, it stored dependent_shard_id NULL and discarded the slug, so
    # the registry knew the exact repository of a shard it had never heard of
    # and kept no record of it.
    #
    # That is the difference between an edge and a lead. dependent_shard_id
    # answers "which row does this point at", and NULL there is a legitimate
    # answer for a dependency on something unregistered. resolved_slug answers
    # "which repository does this name", which is knowable without a row and is
    # what DependencySweep crawls.
    #
    # Nilable, and NULL means "names no repository we can address" rather than
    # "unresolved". A dependency with no source key at all names only a bare
    # string, and a bare name is not a repository: two shards may answer to it.
    alter table_for(Dependency) do
      add resolved_slug : String?
    end

    # The candidate set, indexed for the one query that reads it: slugs naming a
    # repository with no row of its own. Partial rather than a plain index on
    # resolved_slug, because every indexed shard's dependencies are re-resolved
    # on every pass and the overwhelming majority of edges do point at a row we
    # have. Indexing those costs a write per edge to serve a query that excludes
    # them.
    execute <<-SQL
      CREATE INDEX dependencies_unregistered_resolved_slug_index
        ON dependencies (resolved_slug)
        WHERE resolved_slug IS NOT NULL AND dependent_shard_id IS NULL
      SQL
  end

  def rollback
    execute "DROP INDEX IF EXISTS dependencies_unregistered_resolved_slug_index"

    alter table_for(Dependency) do
      remove :resolved_slug
    end
  end
end
