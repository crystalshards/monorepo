# Discovery and indexing entrypoint for the discover-shards Cloud Run Job.
#
# Three phases, one process, one schedule.
#
#   1. seed     read the top of GitHub's star ranking, so the shards people have
#               heard of are in the registry rather than behind the long tail
#   2. sweep    find repositories nobody has told us about, exhaustively
#   3. index    turn the ones already found into pages with content
#
# Nothing else in this repo invokes any of them. The registry indexes a shard when
# somebody posts it, uploads it, or pushes to a repository we already hold a
# webhook for; none of those find a shard nobody has told us about, and none of
# them fill in a shard discovery found six months ago. This binary is what does,
# and Cloud Scheduler is what runs it.
#
# The phases share this process because they share a rate limit. Split across two
# Jobs they would each hold half a budget they cannot see the other spending, and
# the crawl would starve the indexer on exactly the runs where discovery found
# the most to index.
#
# Seeding goes first for the same reason. All three phases read shard.yml files
# out of the same core budget, so whichever runs last is the one a throttled run
# cuts short, and a half-finished run that has seeded the ranking is worth more
# than one that has read another hundred small manifests. The exhaustive sweep
# loses nothing by going second: its cursor advances monotonically, so a page it
# does not reach this run is the page the next run starts on.
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
require "./services/index_sweep"

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

# Both phases are configured before either runs. A bad INDEX_MAX_SHARDS should
# not be discovered forty minutes into a crawl, after the budget is spent.
options = begin
  Discovery::Sweep::Options.from_env
rescue ex : Discovery::Sweep::ConfigurationError
  # Exit 2, not 1. A host that failed and a Job whose environment is wrong send
  # an operator to two different places, and the exit code is the only part of
  # this that a dashboard reads.
  STDERR.puts ex.message
  exit 2
end

index_options = begin
  IndexSweep::Options.from_env
rescue ex : IndexSweep::ConfigurationError
  STDERR.puts ex.message
  exit 2
end

result = Discovery::Sweep.run(options)
Discovery::Sweep.render(result, STDOUT)
STDOUT.puts

# Indexing runs even when the crawl failed. Discovery and indexing fail for
# unrelated reasons: a host refusing a search says nothing about whether the 217
# shards already in the table can be read, and skipping the last phase because
# the ones before it had a bad night is how the registry stays empty through an
# outage that never touched it.
index_report = IndexSweep.run(index_options)
IndexSweep.render(index_report, STDOUT)
STDOUT.flush

# Either half failing fails the Job. `Discovery::Sweep` already folds its own two
# phases into one exit code, so a seeding pass that could not run fails the Job
# through the same path a host does. A run that crawled nothing and a run that
# indexed nothing are both worth a red mark, and collapsing them to the worse of
# the two is what lets one alert cover the Job rather than one per phase.
exit [result.exit_code, index_report.exit_code].max
