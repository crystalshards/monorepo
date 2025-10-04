# JoobQ configuration for background job processing
# This is loaded by both the API server and worker process

require "joobq"

# Parse REDIS_URL to extract host and port
redis_url = URI.parse(ENV.fetch("REDIS_URL", "redis://localhost:6379"))
redis_host = redis_url.host || "localhost"
redis_port = redis_url.port || 6379

# Configure JoobQ with Redis connection
JoobQ.configure do |c|
  c.store = JoobQ::RedisStore.new(host: redis_host, port: redis_port)
end

Log.info { "JoobQ configured with Redis: #{redis_host}:#{redis_port}" }
