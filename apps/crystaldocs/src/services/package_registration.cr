module CrystalDocs
  # Turns a registry fact into the rows the documentation pipeline needs.
  #
  # Before this existed, a Doc row only ever appeared after somebody had
  # already built documentation, which made the lazy build unreachable for
  # every package that had never been built. This closes that loop: the
  # canonical route registers what the registry has already published, and then
  # hands off to the request path that was always there.
  #
  # It registers and nothing else. No build is started here and none may be:
  # a build clones a repository and compiles third party code, so it happens in
  # a Cloud Run Job that holds no credentials, commissioned through
  # `DocBuildRequests`. This service only writes the two rows that give that
  # request something to be about.
  #
  # Every write is an upsert decided by the database rather than by a read
  # followed by a write, because the traffic that reaches it is several readers
  # landing on the same cold URL at once, which is exactly the case
  # read-then-write gets wrong.
  class PackageRegistration
    INSERT_DOC_SQL = <<-SQL
      INSERT INTO docs
        (package_name, current_version, description, repository_url, total_views, created_at, updated_at)
      VALUES ($1, $2, $3, $4, 0, $5, $5)
      ON CONFLICT (package_name) DO NOTHING
      SQL

    # last_updated_at stays NULL. It records when documentation was last built,
    # and nothing has been built yet; filling it in would put a package nobody
    # has documented at the top of a list ordered by that column.
    #
    # The conflict path only ever backfills a commit sha, never overwrites
    # one, and only for a version nothing has successfully built yet. A
    # version already built documents whatever commit was checked out for
    # that build, and the registry's current answer for the same tag is not
    # proof of what that was: the tag can have moved since. Guessing there
    # would let a README's relative reference resolve against a revision the
    # artifact was never compiled from. A version still pending has no such
    # artifact to be wrong about, so recording the registry's current answer
    # is simply recording a fact, not a guess.
    INSERT_VERSION_SQL = <<-SQL
      INSERT INTO doc_versions
        (doc_id, version, published_at, build_status, storage_path, source_commit_sha, created_at, updated_at)
      VALUES ($1, $2, $3, 'pending', $4, $5, $6, $6)
      ON CONFLICT (doc_id, version) DO UPDATE
        SET source_commit_sha = EXCLUDED.source_commit_sha
        WHERE doc_versions.source_commit_sha IS NULL
          AND doc_versions.build_status <> 'success'
          AND EXCLUDED.source_commit_sha IS NOT NULL
      SQL

    # The default version is registry state, not ours, so it is corrected on
    # sight rather than left at whatever the first reader happened to ask for.
    # Predicated on the current value so a concurrent writer with the same
    # answer does not generate a second write.
    UPDATE_CURRENT_VERSION_SQL = <<-SQL
      UPDATE docs
      SET current_version = $2, updated_at = $3
      WHERE package_name = $1
        AND current_version IS DISTINCT FROM $2
      SQL

    # The row for this repository, created if this is the first time anyone has
    # asked for it.
    #
    # `default_version` is the registry's current release and may be nil for a
    # shard with no usable release. It is not the version being requested: a
    # reader asking for an old release must not move the package's default.
    def self.doc_for(
      package : RegistryPackages::Package,
      default_version : String?,
    ) : Doc
      now = Time.utc

      AppDatabase.exec(
        INSERT_DOC_SQL,
        package.slug,
        default_version,
        package.description,
        package.repository_url,
        now
      )

      if default_version
        AppDatabase.exec(UPDATE_CURRENT_VERSION_SQL, package.slug, default_version, now)
      end

      DocQuery.new.preload_doc_versions.package_name(package.slug).first? ||
        raise "docs row for #{package.slug} disappeared immediately after being registered."
    end

    # The version row, created if absent. Registered as pending because that is
    # what it is: published by the registry, not yet built here.
    #
    # storage_path is where the artifact will be, and it is composed from the
    # package key rather than from the shard's name. That is the whole point of
    # the key being host qualified: two repositories publishing a shard called
    # "lsp" write to two different prefixes instead of overwriting each other.
    def self.version_for(doc : Doc, release : RegistryPackages::Release) : DocVersion
      now = Time.utc
      doc_id = doc.id

      AppDatabase.exec(
        INSERT_VERSION_SQL,
        doc_id,
        release.version,
        release.released_at,
        "#{doc.package_name}/#{release.version}",
        release.commit_sha,
        now
      )

      DocVersionQuery.new.doc_id(doc_id).version(release.version).first? ||
        raise "doc_versions row for #{doc.package_name} #{release.version} disappeared immediately after being registered."
    end
  end
end
