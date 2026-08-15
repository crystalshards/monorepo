# One-off publish entrypoint for the Crystal standard library's own
# documentation, built and published exactly the way CrystalShards::CoreDocs
# describes: clone the pinned repository at the compiler's own version,
# compile under whichever sandbox DOCS_SANDBOX selects, validate, publish,
# and record the outcome through the same DocsBuildStatus a shard build uses.
#
# This is not the only way that pipeline runs. docs-launcher's
# BuildDocsWorker reaches the identical CrystalShards::CoreDocs.build_and_publish
# when a build request names the `crystal` package, whether that request came
# from a reader opening a page with no artifact or from crystaldocs's own
# enqueue. This binary exists for the case neither of those cover: there is no
# artifact yet and nobody has asked for one through a page, so nothing would
# ever enqueue the first build. Run it as a Cloud Run Job execution against the
# same image the service runs, with the command `./publish-core-docs`, or
# locally with DOCS_SANDBOX=none and DOCS_SANDBOX_ALLOW_UNSAFE=true. Safe to
# run again: a version already published is left alone by default, its row
# simply marked success again from the artifact already in the bucket, and
# registration is idempotent either way. FORCE_REBUILD=true on this one
# execution is the deliberate exception, a real clone and compile that
# republishes under the same key and records whatever commit that clone
# actually lands on.
#
# Like src/migrate.cr, src/discover_shards.cr and src/reconcile_docs_status.cr,
# and for the same reason, this deliberately does NOT require ./app. That pulls
# config/server.cr, which raises without PORT and SECRET_KEY_BASE, and every
# boot time variable the web app has grown since. None of it is reachable from
# a publish.
#
# What it does require is the two database configs and the object store,
# resolved exactly the way the builder does, from the same variables, with the
# same failure messages: DATABASE_URL, DOCS_DATABASE_URL and DOCS_BUCKET.
# config/object_store_buckets.cr is left out for the same reason
# reconcile_docs_status.cr leaves it out: that file is per-app boot policy
# demanding PACKAGES_BUCKET too, which nothing here reads.
require "./shards"
require "./app_database"
require "./docs_database"
require "../config/database"
require "../config/docs_database"
require "../config/object_store"
# DocsSandbox.timeout_seconds reads CloudTasksConfig.deadline_seconds, so
# whatever loads CoreDocs must have already defined it. The full app gets
# this for free from `services/**`; this entrypoint pulls in only the one
# file that declares it, not the queue machinery around it.
require "./services/docs_build_queue"
require "./services/core_docs"

# Dispatched synchronously so a build's own log lines land ahead of the
# summary this prints with `puts`, matching every sibling entrypoint.
Log.setup(:info, Log::IOBackend.new(STDOUT, dispatcher: :sync))

# Set by the publish-core-docs workflow's force input, arriving as an
# override on this one Job execution rather than a persistent setting or a
# new argument to this binary. Read exactly once, here, so the log line
# below and the behaviour CoreDocs actually takes always agree on what this
# run decided; everything downstream takes `force` as a value, never
# re-reads the environment for it.
force = ENV["FORCE_REBUILD"]? == "true"
Log.info { "publish-core-docs: FORCE_REBUILD=#{force}" }

published =
  begin
    CrystalShards::CoreDocs.build_and_publish(force: force)
  rescue ex : CrystalShards::CoreDocs::VersionMismatch | CrystalStorage::MissingBucket | CrystalShards::DocsSandbox::Unavailable
    # A Job whose environment is wrong and a Job whose work failed send an
    # operator to two different places, matching src/discover_shards.cr and
    # src/reconcile_docs_status.cr: exit 2 names a configuration problem, and
    # the message says exactly which.
    STDERR.puts ex.message
    exit 2
  rescue ex : CrystalShards::CoreDocs::IncompleteArtifact
    # The one refusal this binary exists to demonstrate as well as enforce:
    # a `crystal docs` exit 0 is not evidence the artifact is usable, and one
    # missing the types every other package's cross links depend on is
    # refused rather than published.
    STDERR.puts "Refusing to publish an incomplete artifact: #{ex.message}"
    exit 1
  rescue ex : Exception
    # Everything else CoreDocs.build_and_publish raises has already been
    # recorded against this package and version through DocsBuildStatus,
    # or logged as to why it could not be. Nothing further to add here.
    STDERR.puts ex.message
    exit 1
  end

puts ""
if published.reused_existing
  puts "Core documentation already present for #{CrystalShards::CoreDocs::PACKAGE}@#{CrystalShards::CoreDocs.version}"
  puts "  key: #{published.key}"
  puts "  database row marked success again from the artifact itself"
else
  puts "Published #{CrystalShards::CoreDocs::PACKAGE}@#{CrystalShards::CoreDocs.version}"
  puts "  key:   #{published.key}"
  puts "  bytes: #{published.bytes}"
  puts "  types: #{published.types}"
end
STDOUT.flush
