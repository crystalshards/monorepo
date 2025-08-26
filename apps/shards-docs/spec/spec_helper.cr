require "spec"
require "../src/crystaldocs"

# Test database setup
ENV["DATABASE_URL"] ||= "postgresql://postgres:postgres@localhost:5432/crystaldocs_test"
ENV["REDIS_URL"] ||= "redis://localhost:6379/1"  
ENV["ENV"] = "test"

# Configure test environment
Spec.before_suite do
  puts "Setting up CrystalDocs test environment..."
end

Spec.after_suite do
  puts "Cleaning up CrystalDocs test environment..."
end