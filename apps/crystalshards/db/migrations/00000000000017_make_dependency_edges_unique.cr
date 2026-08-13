class MakeDependencyEdgesUnique::V00000000000017 < Avram::Migrator::Migration::V1
  def migrate
    # A version's dependency set is replaced wholesale: UpdateDependenciesWorker
    # deletes every row for the version and reinserts from the manifest. That is
    # correct on its own and wrong under two passes at once.
    #
    # Two overlapping sweeps do not work on disjoint shards. Both order by the
    # same index_attempted_at staleness cursor and both claim per shard as they
    # reach it, so they collide on the same rows by construction, and the sweep
    # is bounded and resumable precisely so runs CAN overlap. Interleaved, each
    # DELETE takes its snapshot before the other's INSERTs are visible, so
    # neither removes what the other wrote and the version ends up with two
    # copies of every edge.
    #
    # A duplicated edge is not a duplicated row anybody looks at. It is a
    # dependent counted twice in the figure a shard page renders next to its
    # star count, which is the silently-wrong-number failure this whole area
    # keeps producing. The constraint makes the arithmetic impossible to get
    # wrong rather than merely unlikely.
    #
    # Existing duplicates would refuse the index, so they go first. The lowest
    # id wins; the rows are identical in everything the graph reads.
    execute <<-SQL
      DELETE FROM dependencies
      WHERE id NOT IN (
        SELECT MIN(id)
        FROM dependencies
        GROUP BY shard_version_id, name, scope
      )
      SQL

    # Scope is part of the key. A shard legitimately appears twice in one
    # manifest, once under dependencies and once under development_dependencies,
    # and those are two different edges rather than a duplicate.
    execute <<-SQL
      CREATE UNIQUE INDEX dependencies_shard_version_id_name_scope_index
        ON dependencies (shard_version_id, name, scope)
      SQL

    # Redundant now: a B-tree on (shard_version_id, name, scope) already serves
    # every lookup the dropped one did, as a prefix. Keeping both would pay two
    # index writes per edge for one index's worth of reads.
    drop_index table_for(Dependency), [:shard_version_id, :name]
  end

  def rollback
    create_index table_for(Dependency), [:shard_version_id, :name]

    execute "DROP INDEX IF EXISTS dependencies_shard_version_id_name_scope_index"
  end
end
