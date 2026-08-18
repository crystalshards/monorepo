# Documentation warming entrypoint for the warm-popular-docs Cloud Run Job.
#
# Documentation is built the first time somebody asks for a version. That is
# the right default for a catalogue whose long tail is never opened, and the
# wrong one for its head: the first reader of the most depended-upon shard in
# the ecosystem waits minutes for a clone and a compile, and that reader is
# usually the one deciding whether this site is worth using at all.
#
# This warms the head on a schedule so the tail can stay lazy. It commissions
# builds through exactly the same worker a reader's request does, so a warm
# build and a requested one are the same build with the same recorded outcome;
# nothing here is a second pipeline.
#
# Like src/discover_shards.cr and src/migrate.cr, this deliberately does NOT
# require ./app. That pulls config/server.cr, which raises without PORT and
# SECRET_KEY_BASE, and every boot-time variable added to the web app after it.
# None of it is reachable from enqueueing a build.
require "./shards"
require "./app_database"
require "./docs_database"
require "../config/database"
require "../config/docs_database"
require "./models/base_model"
require "./models/mixins/**"
require "./models/**"
require "./queries/mixins/**"
require "./queries/**"
require "./services/git_host_policy"
require "./operations/mixins/**"
require "./operations/**"
require "./services/version_order"
require "./services/index_sweep"
require "./services/docs_warming"
require "./workers/build_docs_worker"

# Synchronously dispatched, so the per-shard lines land ahead of the summary
# this prints with `puts` rather than inside it.
Log.setup(:info, Log::IOBackend.new(STDOUT, dispatcher: :sync))

options =
  begin
    CrystalShards::DocsWarming::Options.from_env
  rescue ex : CrystalShards::DocsWarming::ConfigurationError
    # Exit 2, matching the other Jobs in this app: a Job whose environment is
    # wrong and a Job whose work failed send an operator to two different
    # places, and the exit code is the only part a dashboard reads.
    STDERR.puts ex.message
    exit 2
  end

report = CrystalShards::DocsWarming.run(options)
CrystalShards::DocsWarming.render(report, STDOUT)
STDOUT.flush

exit report.exit_code
