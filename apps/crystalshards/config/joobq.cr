# JoobQ configuration for background job processing
# This is loaded by both the API server and worker process

require "joobq"

# Configure JoobQ client for enqueueing jobs
Joobq.configure do |c|
  c.store = Joobq::RedisStore.new(
    uri: Lucky::Server.settings.redis_url
  )
end

Log.info { "JoobQ configured with Redis: #{Lucky::Server.settings.redis_url}" }
