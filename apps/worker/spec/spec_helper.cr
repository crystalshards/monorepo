require "spec"
require "../src/worker"

# Test database setup
ENV["DATABASE_URL"] ||= "postgresql://postgres:postgres@localhost:5432/crystalshards_test"
ENV["REDIS_URL"] ||= "redis://localhost:6379/3"
ENV["ENV"] = "test"

# Configure test environment
Spec.before_suite do
  puts "Setting up Worker test environment..."
end

Spec.after_suite do
  puts "Cleaning up Worker test environment..."
end