ENV["LUCKY_ENV"] = "test"
ENV["DEV_PORT"] = "5001"
ENV["STORAGE_ENDPOINT"] = "http://localhost:9000"
ENV["DOCS_BUCKET"] = "crystaldocs-test"
# Required by SiteLinks (footer cross links), which has no default in any
# environment, and wanted by the ad strip's house ads so a spec exercises the
# fallback without wiring an origin by hand. `||=` so a spec can still assert
# what happens when one is absent by clearing it, and so CI's own values win
# if they are set there.
ENV["SHARDS_SITE_ORIGIN"] ||= "http://localhost:3000"
ENV["DOCS_SITE_ORIGIN"] ||= "http://localhost:3001"
ENV["GIGS_SITE_ORIGIN"] ||= "http://localhost:3002"
ENV["BITS_SITE_ORIGIN"] ||= "http://localhost:3003"
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
