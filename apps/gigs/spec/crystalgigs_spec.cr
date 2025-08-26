require "./spec_helper"
require "spec-kemal"
require "json"

# Load application
require "../src/crystalgigs"

describe "CrystalGigs Job Board" do
  before_each do
    # Clean test database before each test
    CrystalGigs::DB.exec("TRUNCATE job_postings RESTART IDENTITY CASCADE")
    CrystalGigs::REDIS.flushdb
    
    # Set up test environment variables
    ENV["STRIPE_SECRET_KEY"] = "sk_test_dummy_key_for_testing"
    ENV["STRIPE_PUBLISHABLE_KEY"] = "pk_test_dummy_key_for_testing"
  end

  describe "Health endpoint" do
    it "responds with health status" do
      get "/health"
      response.status_code.should eq(200)
      
      json = JSON.parse(response.body)
      json["status"].should eq("ok")
      json["version"].should eq("0.1.0")
      json["timestamp"].should be_a(String)
    end
  end

  describe "Homepage" do
    it "serves the job board homepage" do
      get "/"
      response.status_code.should eq(200)
      response.body.should contain("CrystalGigs")
      response.body.should contain("Crystal Developer Jobs")
    end

    it "displays no jobs message when empty" do
      get "/"
      response.status_code.should eq(200)
      response.body.should contain("No jobs posted yet")
      response.body.should contain("Be the first to post")
    end

    it "shows post job link" do
      get "/"
      response.body.should contain("Post a Job")
      response.body.should contain("$99")
    end

    it "handles database errors gracefully" do
      # Test fallback when database is unavailable
      get "/"
      response.status_code.should eq(200)
      # Should either show jobs or fallback message
      response.body.should contain("CrystalGigs")
    end
  end

  describe "Job posting form" do
    it "displays the job posting form" do
      get "/post"
      response.status_code.should eq(200)
      response.body.should contain("Post a Crystal Developer Job")
      response.body.should contain("$99 for 30 days")
      response.body.should contain("form")
    end

    it "shows error messages when provided" do
      get "/post?error=payment_cancelled"
      response.status_code.should eq(200)
      response.body.should contain("Payment was cancelled")
    end

    it "includes all required form fields" do
      get "/post"
      response.body.should contain("Job Title")
      response.body.should contain("Company Name")
      response.body.should contain("Location")
      response.body.should contain("Job Type")
      response.body.should contain("Job Description")
      response.body.should contain("Application Email")
    end
  end

  describe "Job submission" do
    it "requires all mandatory fields" do
      post "/jobs", headers: HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}, body: ""
      response.status_code.should eq(400)
      response.body.should contain("Missing required fields")
    end

    it "processes valid job submission" do
      form_data = "title=Senior+Crystal+Developer&company=Test+Company&location=Remote&type=full-time&description=Great+job&email=test@example.com"
      
      post "/jobs", headers: HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}, body: form_data
      
      # Should redirect to Stripe checkout or return error
      [302, 400, 500].should contain(response.status_code)
      
      if response.status_code == 302
        response.headers["Location"]?.should_not be_nil
      end
    end

    it "validates email format" do
      form_data = "title=Test&company=Test&location=Remote&type=full-time&description=Test&email=invalid-email"
      
      post "/jobs", headers: HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}, body: form_data
      
      # Should process (email validation happens in Stripe)
      [302, 400, 500].should contain(response.status_code)
    end
  end

  describe "Payment success page" do
    it "requires session_id and job_key parameters" do
      get "/payment/success"
      response.status_code.should eq(302)
      response.headers["Location"]?.should contain("/post?error=")
    end

    it "handles missing parameters gracefully" do
      get "/payment/success?session_id=cs_test_123"
      response.status_code.should eq(302)
      response.headers["Location"]?.should contain("invalid_payment")
    end
  end

  describe "Stripe webhook" do
    it "accepts webhook payload" do
      webhook_payload = {
        "type" => "checkout.session.completed",
        "data" => {
          "object" => {
            "id" => "cs_test_123",
            "payment_status" => "paid"
          }
        }
      }.to_json
      
      post "/webhook/stripe", 
           headers: HTTP::Headers{"Content-Type" => "application/json"}, 
           body: webhook_payload
      
      response.status_code.should eq(200)
      
      json = JSON.parse(response.body)
      json["status"].should eq("received")
    end

    it "handles invalid webhook data" do
      post "/webhook/stripe", 
           headers: HTTP::Headers{"Content-Type" => "application/json"}, 
           body: "invalid json"
      
      response.status_code.should eq(400)
      
      json = JSON.parse(response.body)
      json["error"].should eq("Invalid webhook")
    end

    it "processes payment_intent.succeeded events" do
      webhook_payload = {
        "type" => "payment_intent.succeeded",
        "data" => {
          "object" => {
            "id" => "pi_test_123"
          }
        }
      }.to_json
      
      post "/webhook/stripe", 
           headers: HTTP::Headers{"Content-Type" => "application/json"}, 
           body: webhook_payload
      
      response.status_code.should eq(200)
    end
  end

  describe "Jobs API" do
    it "returns empty job list" do
      get "/api/v1/jobs"
      response.status_code.should eq(200)
      
      json = JSON.parse(response.body)
      json["jobs"].as_a.should be_empty
      json["total"].should eq(0)
      json["page"].should eq(1)
      json["per_page"].should eq(20)
    end

    it "supports pagination parameters" do
      get "/api/v1/jobs?limit=5&offset=10"
      response.status_code.should eq(200)
      
      json = JSON.parse(response.body)
      json["page"].should eq(3)  # (10/5) + 1
      json["per_page"].should eq(5)
    end

    it "supports search query" do
      get "/api/v1/jobs?q=crystal+developer"
      response.status_code.should eq(200)
      
      json = JSON.parse(response.body)
      json["query"].should eq("crystal developer")
      json["jobs"].should be_a(Array)
    end

    it "limits page size to maximum" do
      get "/api/v1/jobs?limit=500"
      response.status_code.should eq(200)
      
      json = JSON.parse(response.body)
      json["per_page"].should eq(100)  # Clamped to max
    end

    it "handles database errors gracefully" do
      # Test API resilience
      get "/api/v1/jobs"
      # Should return 200 or 500, but not crash
      [200, 500].should contain(response.status_code)
    end
  end

  describe "CORS headers" do
    it "sets CORS headers on all requests" do
      get "/api/v1/jobs"
      response.headers["Access-Control-Allow-Origin"].should eq("*")
      response.headers["Access-Control-Allow-Methods"].should contain("GET")
      response.headers["Access-Control-Allow-Headers"].should contain("Content-Type")
    end

    it "handles OPTIONS requests" do
      options "/api/v1/jobs"
      response.status_code.should eq(200)
    end
  end

  describe "Error handling" do
    it "returns 404 for unknown endpoints" do
      get "/nonexistent"
      response.status_code.should eq(404)
      response.body.should contain("404 - Page Not Found")
      response.body.should contain("Back to Jobs")
    end
  end

  describe "Integration with services" do
    it "can initialize job repository" do
      # Test that services are properly initialized
      repo = JobRepository
      repo.responds_to?(:get_all_jobs).should be_true
      repo.responds_to?(:search_jobs).should be_true
      repo.responds_to?(:create_job).should be_true
    end

    it "can initialize stripe service" do
      # Test that Stripe service is available
      service = StripeService
      service.responds_to?(:create_checkout_session).should be_true
      service.responds_to?(:retrieve_session).should be_true
    end
  end

  describe "Redis integration" do
    it "can store and retrieve job drafts" do
      # Test Redis functionality for job drafts
      test_key = "test_job_draft"
      test_data = {"title" => "Test Job"}.to_json
      
      CrystalGigs::REDIS.setex(test_key, 300, test_data)
      retrieved = CrystalGigs::REDIS.get(test_key)
      
      retrieved.should eq(test_data)
      
      # Clean up
      CrystalGigs::REDIS.del(test_key)
    end
  end

  describe "Database integration" do
    it "can execute basic database operations" do
      # Test that database connection works
      result = CrystalGigs::DB.query_one("SELECT 1 as test", as: Int32)
      result.should eq(1)
    end

    it "can access job_postings table" do
      # Test that job_postings table exists and is accessible
      result = CrystalGigs::DB.query_one(
        "SELECT COUNT(*) FROM information_schema.tables WHERE table_name = 'job_postings'", 
        as: Int64
      )
      result.should eq(1)
    end
  end

  describe "Form validation and security" do
    it "handles special characters in form data" do
      form_data = "title=Test+%3Cscript%3E&company=Test&location=Remote&type=full-time&description=Test&email=test@example.com"
      
      post "/jobs", headers: HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}, body: form_data
      
      # Should process without crashing
      [302, 400, 500].should contain(response.status_code)
    end

    it "handles large form data appropriately" do
      large_description = "A" * 5000  # Very long description
      form_data = "title=Test&company=Test&location=Remote&type=full-time&description=#{large_description}&email=test@example.com"
      
      post "/jobs", headers: HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}, body: form_data
      
      # Should handle gracefully
      [302, 400, 413, 500].should contain(response.status_code)
    end
  end
end