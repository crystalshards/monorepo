require "./app"

# Worker process entry point
# This runs background jobs using JoobQ

module CrystalShards
  class Worker
    def self.run
      Log.info { "Starting CrystalShards worker process..." }

      # Configure JoobQ
      JoobQ.configure do |c|
        c.store = JoobQ::RedisStore.new(
          uri: ENV.fetch("REDIS_URL", "redis://localhost:6379/0")
        )

        # Configure queues with priorities
        c.queues = {
          "indexing" => 5,  # Higher priority for indexing
          "docs"     => 3,  # Medium priority for docs
          "default"  => 1   # Lower priority for misc tasks
        }
      end

      Log.info { "JoobQ configured with Redis store" }

      # Start processing jobs
      JoobQ.start

      Log.info { "Worker process started and ready to process jobs" }

      # Keep the process running
      sleep
    end
  end
end

# Run the worker
CrystalShards::Worker.run
