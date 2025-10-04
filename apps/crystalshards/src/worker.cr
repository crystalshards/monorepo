require "./app"

# Worker process entry point
# This runs background jobs using JoobQ

module CrystalShards
  class Worker
    def self.run
      Log.info { "Starting CrystalShards worker process..." }

      # Parse REDIS_URL to extract host and port
      redis_url = URI.parse(ENV.fetch("REDIS_URL", "redis://localhost:6379"))
      redis_host = redis_url.host || "localhost"
      redis_port = redis_url.port || 6379

      # Configure JoobQ
      JoobQ.configure do |c|
        c.store = JoobQ::RedisStore.new(host: redis_host, port: redis_port)

        # Configure queues with priorities
        c.queues = {
          "indexing" => 5,  # Higher priority for indexing
          "docs"     => 3,  # Medium priority for docs
          "default"  => 1   # Lower priority for misc tasks
        }
      end

      Log.info { "JoobQ configured with Redis: #{redis_host}:#{redis_port}" }

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
