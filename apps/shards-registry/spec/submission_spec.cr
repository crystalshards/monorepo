require "./spec_helper"
require "../src/services/shard_submission_service"

describe CrystalShards::ShardSubmissionService do
  describe "GitHub URL validation" do
    it "validates valid GitHub URLs" do
      service = create_submission_service
      
      # Test with a mock GitHub repository that has proper shard.yml
      mock_github_responses
      
      result = service.submit_from_github("https://github.com/crystal-lang/crystal")
      
      result[:errors].should_not contain("Invalid GitHub URL format")
    end
    
    it "rejects invalid URLs" do
      service = create_submission_service
      
      result = service.submit_from_github("not-a-url")
      
      result[:errors].should contain("Invalid GitHub URL format")
      result[:shard].should be_nil
    end
    
    it "rejects non-GitHub URLs" do
      service = create_submission_service
      
      result = service.submit_from_github("https://gitlab.com/user/repo")
      
      result[:errors].should contain("Invalid GitHub URL format")
      result[:shard].should be_nil
    end
  end
  
  describe "duplicate detection" do
    it "prevents duplicate submissions by GitHub URL" do
      service = create_submission_service
      mock_github_responses
      
      # First submission
      result1 = service.submit_from_github("https://github.com/crystal-lang/crystal")
      result1[:shard].should_not be_nil
      
      # Second submission of same URL
      result2 = service.submit_from_github("https://github.com/crystal-lang/crystal")
      result2[:errors].should contain(/already exists/)
    end
  end
  
  describe "shard.yml parsing" do
    it "extracts information from shard.yml" do
      service = create_submission_service
      mock_github_responses_with_custom_shard_yml
      
      result = service.submit_from_github("https://github.com/test/example")
      
      result[:shard].try do |shard|
        shard.name.should eq("example")
        shard.description.should eq("A test shard")
        shard.license.should eq("MIT")
      end
    end
  end
  
  private def create_submission_service
    # Use in-memory database for testing
    db = DB.open("postgres://postgres:password@localhost/test")
    redis = Redis.new(url: "redis://localhost:6379/1")
    
    CrystalShards::ShardSubmissionService.new(db, redis)
  end
  
  private def mock_github_responses
    # Mock HTTP responses would go here in a real test
    # For now, this is a placeholder for integration testing
  end
  
  private def mock_github_responses_with_custom_shard_yml
    # Mock custom shard.yml responses
  end
end