# Mosquito configuration for background job processing
# This is loaded by both the API server and worker process

require "mosquito"

# Configure Mosquito with Redis connection
Mosquito.configure do |settings|
  settings.redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379")
end

Log.info { "Mosquito configured with #{ENV.fetch("REDIS_URL", "redis://localhost:6379")}" }
