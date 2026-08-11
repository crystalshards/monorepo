# Schema migration entrypoint for the crystalshards-migrate Cloud Run Job.
#
# This deliberately does NOT require ./app. Loading the whole application pulls in
# every file under config/, and each of those raises at load time when its own
# production variable is absent: config/server.cr reads PORT and SECRET_KEY_BASE,
# config/email.cr calls exit(1) without SEND_GRID_KEY, and individual apps add more
# over time. None of it is reachable from a migration, so requiring the app would
# hand the one identity holding DDL rights a session signing key and a mail key to
# run a DDL statement, and every new boot time config would silently break
# migrations until somebody remembered to add another variable to the Job.
#
# A migration needs a database connection and the migration classes. That is all
# this requires, so the Job needs only DATABASE_URL.
require "./shards"
require "./app_database"
require "../config/database"
require "../db/migrations/**"

Avram::Migrator::Runner.new.run_pending_migrations
