# Discovery sweep entrypoint for the discover-shards Cloud Run Job.
#
# Nothing else in this repo invokes the crawler. The registry indexes a shard when
# somebody posts it, uploads it, or pushes to a repository we already hold a
# webhook for; none of those find a shard nobody has told us about. This binary is
# what does, and Cloud Scheduler is what runs it.
#
# It is a Job rather than an HTTP route because a sweep of thousands of
# repositories is a task, not a request: it runs for minutes, it needs no caller
# waiting on it, and its result is a row per host rather than a response body.
#
# Like src/migrate.cr and for the same reason, this deliberately does NOT require
# ./app. That pulls config/server.cr, which raises without PORT and
# SECRET_KEY_BASE, and config/object_store_buckets.cr, which raises without
# DOCS_BUCKET, and every config file added after them. None of it is reachable
# from a crawl, so requiring the app would hand a sweep a session signing key and
# a bucket name in order to read shard.yml files, and would then break the Job
# every time somebody added a new boot-time variable to the web app.
#
# What a sweep needs is a database connection, the models and operations discovery
# writes through, and the crawlers. So DATABASE_URL is the only variable this
# binary requires. The host credentials are all optional and independent: a host
# with one is crawled, a host without one is skipped by name, and the run still
# succeeds.
require "./shards"
require "./app_database"
require "../config/database"
require "./models/base_model"
require "./models/mixins/**"
require "./models/**"
require "./queries/mixins/**"
require "./queries/**"
require "./operations/mixins/**"
require "./operations/**"
require "./services/discovery/sweep"

# config/log.cr is not required here: it configures Lucky's request logging and
# pulls the framework in with it. A Job wants its own logs on stdout, in order,
# ahead of the summary this prints at the end.
#
# Dispatched synchronously on purpose. The default backend hands lines to another
# fiber, which for a process that also writes a summary with `puts` means the
# progress lines land inside the summary rather than before it. Measured, not
# assumed: the first build of this printed all four skip lines underneath the
# Skipped block they were describing.
Log.setup(:info, Log::IOBackend.new(STDOUT, dispatcher: :sync))

options = begin
  Discovery::Sweep::Options.from_env
rescue ex : Discovery::Sweep::ConfigurationError
  # Exit 2, not 1. A host that failed and a Job whose environment is wrong send
  # an operator to two different places, and the exit code is the only part of
  # this that a dashboard reads.
  STDERR.puts ex.message
  exit 2
end

result = Discovery::Sweep.run(options)
Discovery::Sweep.render(result, STDOUT)
STDOUT.flush

exit result.exit_code
