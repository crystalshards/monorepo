require "./app"

# Worker process entry point
# This runs background jobs using Mosquito

module CrystalShards
  class Worker
    def self.run
      Log.info { "Starting CrystalShards worker process..." }

      # Configure Mosquito
      Mosquito.configure do |settings|
        settings.redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379")
      end

      Log.info { "Mosquito configured with #{ENV.fetch("REDIS_URL", "redis://localhost:6379")}" }

      # Start processing jobs
      Mosquito::Runner.start

      Log.info { "Worker process started and ready to process jobs" }
    end
  end
end

# Run the worker
CrystalShards::Worker.run
