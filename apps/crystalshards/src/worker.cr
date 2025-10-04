require "./app"

# Worker process entry point
# This runs background jobs using JoobQ

module CrystalShards
  class Worker
    def self.run
      Log.info { "Starting CrystalShards worker process..." }

      # Configure JoobQ
      Joobq.configure do |c|
        c.store = Joobq::RedisStore.new(
          uri: ENV.fetch("REDIS_URL", "redis://localhost:6379/0")
        )
        c.registry = Joobq::InMemoryRegistry.new
      end

      # Register workers
      Joobq.registry.register(Workers::IndexShardWorker.new)
      Joobq.registry.register(Workers::BuildDocsWorker.new)
      Joobq.registry.register(Workers::UpdateDependenciesWorker.new)

      Log.info { "Registered #{Joobq.registry.size} workers" }

      # Start processing
      Joobq.start

      Log.info { "Worker process started and ready to process jobs" }

      # Keep the process running
      sleep
    end
  end
end

# Run the worker
CrystalShards::Worker.run
