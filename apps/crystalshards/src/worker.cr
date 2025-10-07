require "./app"

# Worker process entry point
# This runs background jobs using JoobQ

module CrystalShards
  class Worker
    def self.run
      Log.info { "Starting CrystalShards worker process..." }

      # Configure JoobQ (v0.3.x)
      JoobQ.configure do
        # Define queues: name, workers, job types
        queue "indexing", 5, Workers::IndexShardWorker
        queue "docs", 3, Workers::BuildDocsWorker
        queue "default", 2, Workers::UpdateDependenciesWorker
      end

      Log.info { "JoobQ configured with #{ENV.fetch("REDIS_URL", "redis://localhost:6379")}" }

      # Start processing jobs
      JoobQ.forge

      Log.info { "Worker process started and ready to process jobs" }

      # Keep the process running
      sleep
    end
  end
end

# Run the worker
CrystalShards::Worker.run
