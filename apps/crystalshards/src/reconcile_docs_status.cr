# One-off reconciliation entrypoint: mark the documentation that already exists
# as documentation that exists.
#
# doc_versions.build_status was written once at registration and never again by
# anything until the builder was taught to write it, so every version built
# before that still says 'pending' and the documentation site's cross-package
# links are off for the entire existing catalogue. No build will fix them,
# because no build is going to be run again for a version that already has its
# artifact. This is what fixes them, from the artifacts themselves. See
# `CrystalShards::DocsStatusReconciliation` for what it will and will not infer.
#
# Run it as a Cloud Run Job execution against the same image the service runs,
# with the command `./reconcile-docs-status`. It is idempotent, so a run that is
# interrupted is repaired by running it again.
#
# Like src/migrate.cr and src/discover_shards.cr, and for the same reason, this
# deliberately does NOT require ./app. That pulls config/server.cr, which raises
# without PORT and SECRET_KEY_BASE, and every boot-time variable the web app
# grows after it. None of it is reachable from here.
#
# What it does require is the two database configs and the object store, so it
# resolves its connections exactly the way the builder does, from the same
# variables, with the same failure messages: DATABASE_URL, DOCS_DATABASE_URL and
# DOCS_BUCKET.
#
# config/object_store_buckets.cr is deliberately left out. That file is per-app
# boot policy and demands PACKAGES_BUCKET as well, which this never reads. The
# docs bucket is still resolved with no default and no guess: `CrystalStorage`
# raises `MissingBucket` naming DOCS_BUCKET on first touch, which happens below
# before any row is read.
require "./shards"
require "./app_database"
require "./docs_database"
require "../config/database"
require "../config/docs_database"
require "../config/object_store"
require "./services/docs_status_reconciliation"

# config/log.cr is not required: it configures Lucky's request logging and pulls
# the framework in with it. Dispatched synchronously so the per-version lines
# land ahead of the summary this prints with `puts` rather than inside it.
Log.setup(:info, Log::IOBackend.new(STDOUT, dispatcher: :sync))

report =
  begin
    CrystalShards::DocsStatusReconciliation.run
  rescue ex : CrystalStorage::MissingBucket
    # Exit 2, matching src/discover_shards.cr: a Job whose environment is wrong
    # and a Job whose work failed send an operator to two different places, and
    # the exit code is the only part of this a dashboard reads.
    STDERR.puts ex.message
    exit 2
  rescue ex : CrystalStorage::Unavailable
    # Nothing was written. The candidates are read from the store's listing
    # before any update, so a store that could not answer stops the run rather
    # than marking part of the catalogue from a partial view of it.
    STDERR.puts "The docs bucket could not be listed, so nothing was reconciled: #{ex.message}"
    exit 1
  end

CrystalShards::DocsStatusReconciliation.render(report, STDOUT)
STDOUT.flush
