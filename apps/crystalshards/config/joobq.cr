# JoobQ configuration for background job processing
# This is loaded by both the API server and worker process

require "joobq"

# JoobQ configuration is handled in the worker process
# For the API server, we just need to have JoobQ available to enqueue jobs
# The Redis connection is configured via environment variables:
# REDIS_HOST, REDIS_PORT, REDIS_DB, etc.

Log.info { "JoobQ available for job enqueueing" }
