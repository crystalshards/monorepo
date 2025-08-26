require "spec"
require "../src/crystalgigs"

# Test database setup
ENV["DATABASE_URL"] ||= "postgresql://postgres:postgres@localhost:5432/crystalgigs_test"
ENV["REDIS_URL"] ||= "redis://localhost:6379/2"
ENV["ENV"] = "test"

# Configure test environment
Spec.before_suite do
  puts "Setting up CrystalGigs test environment..."
end

Spec.after_suite do
  puts "Cleaning up CrystalGigs test environment..."
end