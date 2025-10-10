ENV["LUCKY_ENV"] = "test"
ENV["DEV_PORT"] = "5001"
require "spec"

# Load config (minimal set for workers)
require "../config/env"
require "../config/database"
require "../config/minio"
require "../config/joobq"

# Load app dependencies except for actions (which require the server)
require "../src/shards"
require "../src/app_database"
require "../src/models/base_model"
require "../src/models/**"
require "../src/queries/**"
require "../src/operations/mixins/**"
require "../src/operations/**"
require "../src/workers/**"
require "../src/providers/**"
require "../src/services/**"
require "../db/migrations/**"

# Load test support
require "./support/factories/**"
require "./support/mocks/**"

# Database should already be created and migrated in test environment

# Clean database between specs
Spec.before_each do
  AppDatabase.truncate
end
