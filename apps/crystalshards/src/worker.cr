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

      # JoobQ.forge starts JoobQ.queues, which QueueFactory builds from
      # config.queue_configs. Assigning config.queues directly does nothing:
      # forge never reads that hash, so the worker would idle with no queues.
      JoobQ::QueueFactory.register_job_type(IndexShardWorker)
      JoobQ::QueueFactory.register_job_type(BuildDocsWorker)
      JoobQ::QueueFactory.register_job_type(UpdateDependenciesWorker)

      JoobQ::QueueFactory.populate_schema_registry(JoobQ.config.job_registry)

      JoobQ.config.queue_configs["index"] = {job_class_name: "IndexShardWorker", workers: 5, throttle: nil}
      JoobQ.config.queue_configs["docs"] = {job_class_name: "BuildDocsWorker", workers: 3, throttle: nil}
      JoobQ.config.queue_configs["deps"] = {job_class_name: "UpdateDependenciesWorker", workers: 2, throttle: nil}

      Log.info { "JoobQ configured with #{ENV.fetch("REDIS_URL", "redis://localhost:6379")}" }

      # Start processing jobs
      JoobQ.forge

      Log.info { "Worker process started and ready to process jobs" }
    end
  end
end

# Run the worker
CrystalShards::Worker.run
