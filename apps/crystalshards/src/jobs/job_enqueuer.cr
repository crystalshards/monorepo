require "../workers/*"

module CrystalShards::Jobs
  # Helper module for enqueueing background jobs
  # Include this in actions/operations that need to enqueue work
  #
  # Every job is keyed on a shard's canonical slug ("github.com/kemalcr/kemal").
  # The wire field is still called shard_name because that is the queue's
  # format and crystaldocs produces it, but a bare name cannot say which of two
  # same-named shards a job is for, so callers here pass identity.
  module JobEnqueuer
    # Enqueue a job to index a shard
    def enqueue_index_shard(canonical_slug : String, version : String)
      IndexShardWorker.enqueue(shard_name: canonical_slug, version: version)
      Log.info { "Enqueued IndexShardWorker for #{canonical_slug}@#{version}" }
    end

    # Enqueue a job to build documentation
    def enqueue_build_docs(canonical_slug : String, version : String)
      BuildDocsWorker.enqueue(shard_name: canonical_slug, version: version)
      Log.info { "Enqueued BuildDocsWorker for #{canonical_slug}@#{version}" }
    end

    # Enqueue a job to update dependencies
    def enqueue_update_dependencies(canonical_slug : String, version : String)
      UpdateDependenciesWorker.enqueue(shard_name: canonical_slug, version: version)
      Log.info { "Enqueued UpdateDependenciesWorker for #{canonical_slug}@#{version}" }
    end

    # Enqueue all indexing jobs for a new shard version
    def enqueue_full_index(canonical_slug : String, version : String)
      enqueue_index_shard(canonical_slug, version)
      enqueue_build_docs(canonical_slug, version)
      enqueue_update_dependencies(canonical_slug, version)
      Log.info { "Enqueued full indexing pipeline for #{canonical_slug}@#{version}" }
    end
  end
end
