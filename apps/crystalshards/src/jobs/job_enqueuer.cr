require "joobq"

module CrystalShards::Jobs
  # Helper module for enqueueing background jobs
  # Include this in actions/operations that need to enqueue work
  module JobEnqueuer
    # Configure JoobQ client (call this in config)
    def self.configure
      Joobq.configure do |c|
        c.store = Joobq::RedisStore.new(
          uri: ENV.fetch("REDIS_URL", "redis://localhost:6379/0")
        )
      end
    end

    # Enqueue a job to index a shard
    def enqueue_index_shard(shard_name : String, version : String)
      Joobq.enqueue(
        "index_shard",
        {shard_name: shard_name, version: version}
      )
      Log.info { "Enqueued IndexShardWorker for #{shard_name}@#{version}" }
    end

    # Enqueue a job to build documentation
    def enqueue_build_docs(shard_name : String, version : String)
      Joobq.enqueue(
        "build_docs",
        {shard_name: shard_name, version: version}
      )
      Log.info { "Enqueued BuildDocsWorker for #{shard_name}@#{version}" }
    end

    # Enqueue a job to update dependencies
    def enqueue_update_dependencies(shard_name : String, version : String)
      Joobq.enqueue(
        "update_dependencies",
        {shard_name: shard_name, version: version}
      )
      Log.info { "Enqueued UpdateDependenciesWorker for #{shard_name}@#{version}" }
    end

    # Enqueue all indexing jobs for a new shard version
    def enqueue_full_index(shard_name : String, version : String)
      enqueue_index_shard(shard_name, version)
      enqueue_build_docs(shard_name, version)
      enqueue_update_dependencies(shard_name, version)
      Log.info { "Enqueued full indexing pipeline for #{shard_name}@#{version}" }
    end
  end
end
