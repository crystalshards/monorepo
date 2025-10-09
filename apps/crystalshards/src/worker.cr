require "./app"

# Worker process entry point
# This runs background jobs using JoobQ

module CrystalShards
  class Worker
    def self.run
      Log.info { "Starting CrystalShards worker process..." }

      # Configure JoobQ
      JoobQ.configure do |config|
        config.default_queue = "default"
        config.retries = 3
        config.expires = 1.day
      end

      # Register job types and create queues
      JoobQ::QueueFactory.register_job_type(IndexShardWorker)
      JoobQ::QueueFactory.register_job_type(BuildDocsWorker)
      JoobQ::QueueFactory.register_job_type(UpdateDependenciesWorker)

      # Populate schema registry
      JoobQ::QueueFactory.populate_schema_registry(JoobQ.config.job_registry)

      # Create queues manually
      JoobQ.config.queues["index"] = JoobQ::Queue(IndexShardWorker).new("index", 5, nil)
      JoobQ.config.queues["docs"] = JoobQ::Queue(BuildDocsWorker).new("docs", 3, nil)
      JoobQ.config.queues["deps"] = JoobQ::Queue(UpdateDependenciesWorker).new("deps", 2, nil)

      Log.info { "JoobQ configured with #{ENV.fetch("REDIS_URL", "redis://localhost:6379")}" }

      # Start processing jobs
      JoobQ.forge

      Log.info { "Worker process started and ready to process jobs" }
    end
  end
end

# Run the worker
CrystalShards::Worker.run
