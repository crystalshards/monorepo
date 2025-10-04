# JoobQ configuration for background job processing
# This is loaded by both the API server and worker process

require "joobq"

# Configure JoobQ client for enqueueing jobs
redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379/0")

JoobQ.configure do |c|
  c.store = JoobQ::RedisStore.new(uri: redis_url)
end

Log.info { "JoobQ configured with Redis: #{redis_url}" }
