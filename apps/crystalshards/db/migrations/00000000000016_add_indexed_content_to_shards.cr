class AddIndexedContentToShards::V00000000000016 < Avram::Migrator::Migration::V1
  def migrate
    # Discovery writes identity and stops. Everything below is what a shard page
    # needs and did not have, which is why 217 rows render as empty links.
    alter table_for(Shard) do
      # Repository facts. All nilable, and NULL means "not fetched", never zero
      # or false. A permanent 0 star count reads as "nobody uses this", which is
      # a different and wrong claim from "we have not looked yet".
      add topics : Array(String), default: [] of String
      add default_branch : String?
      add pushed_at : Time?
      add archived : Bool?

      # The version a page shows by default. Denormalised so a list of shards
      # costs one query rather than one per row, and rewritten by the indexer on
      # every pass so it cannot drift from shard_versions.
      add latest_version : String?

      # The indexing cursor lives on the row rather than in a separate table.
      # A pass takes the stalest N by index_attempted_at, so progress is
      # monotonic and a shard cannot be skipped forever.
      #
      #   index_attempted_at  claimed, written before the fetch
      #   indexed_at          finished successfully
      #   index_error         finished and failed, with the reason
      #
      # attempted set with both of the others nil is a run that died mid-shard.
      # That row is visibly incomplete, sorts to the back, and is picked up
      # again on a later pass rather than blocking the head of the queue.
      add indexed_at : Time?
      add index_attempted_at : Time?
      add index_error : String?
    end

    # The order every indexing pass reads in. NULLS FIRST because a shard that
    # has never been attempted is the stalest thing there is.
    execute <<-SQL
      CREATE INDEX shards_index_attempted_at_index
        ON shards (index_attempted_at ASC NULLS FIRST)
      SQL

    alter table_for(ShardVersion) do
      # `version` is the normalised display string ("1.12.0"). `ref` is what you
      # actually check out, which is usually "v1.12.0" and for an untagged
      # repository is a branch name. Neither derives from the other.
      add ref : String?

      # "tag" or "branch". A repository with no tags still has a default branch
      # and gets one row describing it honestly, rather than being skipped and
      # rendering as a shard with no versions at all.
      add source : String, default: "tag"

      # The manifest as fetched, and why there is not one. Storing the raw text
      # means a parser change can re-read history without spending rate limit,
      # and spec_error means "no shard.yml at this tag" is recorded rather than
      # looking identical to "not indexed yet".
      add spec_yaml : String?
      add spec_error : String?

      # The app-versus-library signal, stored as the facts rather than reduced
      # to a boolean. A library that also ships a CLI has both, and any hard
      # classifier gets that wrong in both directions without saying so.
      add targets : JSON::Any?
      add executables : JSON::Any?

      add indexed_at : Time?
    end
  end

  def rollback
    alter table_for(ShardVersion) do
      remove :ref
      remove :source
      remove :spec_yaml
      remove :spec_error
      remove :targets
      remove :executables
      remove :indexed_at
    end

    execute "DROP INDEX IF EXISTS shards_index_attempted_at_index"

    alter table_for(Shard) do
      remove :topics
      remove :default_branch
      remove :pushed_at
      remove :archived
      remove :latest_version
      remove :indexed_at
      remove :index_attempted_at
      remove :index_error
    end
  end
end
