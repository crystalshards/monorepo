# JoobQ configuration for background job processing
# This is loaded by both the API server and worker process

require "joobq"

# Configure JoobQ client for enqueueing jobs
JoobQ.configure do |c|
  c.store = JoobQ::RedisStore.new(
    uri: Lucky::Server.settings.redis_url
  )
end

Log.info { "JoobQ configured with Redis: #{Lucky::Server.settings.redis_url}" }
