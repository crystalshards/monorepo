require "spec"
require "../src/crystalshards"

# Test database setup
ENV["DATABASE_URL"] ||= "postgresql://postgres:postgres@localhost:5432/crystalshards_test"
ENV["REDIS_URL"] ||= "redis://localhost:6379/0"
ENV["ENV"] = "test"

# Configure test database
Spec.before_suite do
  # Database setup would go here
  puts "Setting up test environment..."
end

Spec.after_suite do
  # Database cleanup would go here  
  puts "Cleaning up test environment..."
end