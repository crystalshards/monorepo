ENV["LUCKY_ENV"] = "test"
ENV["DEV_PORT"] = "5001"
ENV["STORAGE_ENDPOINT"] = "http://localhost:9000"
ENV["DOCS_BUCKET"] = "crystaldocs-test"
# Not required outside production, but specs want house ads on by default so
# they can exercise the fallback without each one wiring an origin by hand.
# `||=` so a spec can still assert what happens when it is absent by clearing
# it, and so CI's own value wins if one is set there.
ENV["GIGS_SITE_ORIGIN"] ||= "http://localhost:3002"
require "spec"
require "../src/app"
require "./support/**"
require "../db/migrations/**"

# Add/modify files in spec/setup to start/configure programs or run hooks
#
# By default there are scripts for setting up and cleaning the database,
# configuring LuckyFlow, starting the app server, etc.
require "./setup/**"

include Carbon::Expectations
include Lucky::RequestExpectations

Avram::Migrator::Runner.new.ensure_migrated!
Avram::SchemaEnforcer.ensure_correct_column_mappings!
Habitat.raise_if_missing_settings!
