ENV["LUCKY_ENV"] = "test"
ENV["DEV_PORT"] = "5001"
ENV["GITHUB_WEBHOOK_SECRET"] ||= "test_webhook_secret_for_specs"
require "spec"
require "../src/app"
require "./support/**"
require "./support/worker_mocks"
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
