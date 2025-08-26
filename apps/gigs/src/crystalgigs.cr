require "kemal"
require "pg"
require "redis"
require "jwt"
require "stripe"
require "dotenv"

# Load application services
require "./services/stripe_service"
require "./repositories/job_repository"
require "./metrics"

# Load environment variables
Dotenv.load

module CrystalGigs
  VERSION = "0.1.0"
  
  # Configuration
  DATABASE_URL = ENV["DATABASE_URL"]? || "postgres://postgres:password@localhost/crystalgigs_development"
  REDIS_URL = ENV["REDIS_URL"]? || "redis://localhost:6379"
  STRIPE_SECRET_KEY = ENV["STRIPE_SECRET_KEY"]? || ""
  STRIPE_PUBLISHABLE_KEY = ENV["STRIPE_PUBLISHABLE_KEY"]? || ""
  
  # Initialize database connection
  DB = PG.connect(DATABASE_URL)
  
  # Initialize Redis connection
  REDIS = Redis.new(url: REDIS_URL)
  
  # Initialize Stripe
  Stripe.api_key = STRIPE_SECRET_KEY if !STRIPE_SECRET_KEY.empty?
  
  # Add metrics middleware
  add_handler Metrics::MetricsHandler.new
  
  # Health check endpoint
  get "/health" do |env|
    env.response.content_type = "application/json"
    {
      status: "ok",
      version: VERSION,
      timestamp: Time.utc.to_s
    }.to_json
  end
  
  # Prometheus metrics endpoint
  get "/metrics" do |env|
    env.response.content_type = "text/plain; version=0.0.4; charset=utf-8"
    
    # Update database connections gauge
    begin
      result = DB.query("SELECT count(*) FROM pg_stat_activity")
      result.each do |row|
        Metrics::DATABASE_CONNECTIONS.set(row[0].as(Int64).to_f64)
      end
    rescue
      # Ignore database errors for metrics collection
    end
    
    Metrics::REGISTRY.to_prometheus
  end
  
  # Job board homepage
  get "/" do |env|
    begin
      # Get recent jobs from database
      jobs = JobRepository.get_all_jobs(approved_only: true, limit: 10, offset: 0)
      
      jobs_html = if jobs.empty?
        <<-HTML
        <div style="text-align: center; padding: 60px 20px; color: #666;">
          <h3>No jobs posted yet</h3>
          <p>Be the first to post a Crystal developer job!</p>
          <a href="/post" class="btn btn-post">Post a Job ($99)</a>
        </div>
        HTML
      else
        jobs.map do |job|
          description = job["description"].as_s
          description_preview = description.size > 150 ? "#{description[0..150]}..." : description
          
          <<-HTML
          <div class="job-card">
            <div class="job-title">#{job["title"].as_s}</div>
            <div class="job-company">#{job["company"].as_s}</div>
            <div class="job-location">#{job["location"].as_s}</div>
            #{job["salary_range"].as_s? ? %(<div class="job-salary">#{job["salary_range"].as_s}</div>) : ""}
            <p>#{description_preview}</p>
            <div style="margin-top: 15px; display: flex; justify-content: space-between; align-items: center;">
              <span class="job-type" style="background: #e9ecef; padding: 4px 8px; border-radius: 4px; font-size: 12px;">
                #{job["job_type"].as_s.capitalize}
              </span>
              <span style="font-size: 14px; color: #999;">
                #{Time.parse_iso8601(job["created_at"].as_s).to_s("%B %d, %Y")}
              </span>
            </div>
          </div>
          HTML
        end.join("\n")
      end
      
      <<-HTML
      <!DOCTYPE html>
      <html>
      <head>
        <title>CrystalGigs - Crystal Developer Jobs</title>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 0; background: #f8f9fa; }
          .header { background: white; padding: 20px; border-bottom: 1px solid #ddd; }
          .container { max-width: 1200px; margin: 0 auto; padding: 20px; }
          .hero { text-align: center; margin-bottom: 40px; }
          .jobs { display: grid; gap: 20px; }
          .job-card { background: white; padding: 20px; border-radius: 8px; border: 1px solid #ddd; }
          .job-title { font-size: 18px; font-weight: 600; margin-bottom: 10px; }
          .job-company { color: #666; margin-bottom: 10px; font-weight: 500; }
          .job-location { color: #888; font-size: 14px; margin-bottom: 8px; }
          .job-salary { color: #28a745; font-weight: 600; margin-bottom: 10px; }
          .btn { background: #007bff; color: white; padding: 10px 20px; text-decoration: none; border-radius: 4px; display: inline-block; }
          .btn-post { background: #28a745; }
          .nav { display: flex; justify-content: space-between; align-items: center; }
          .stats { text-align: center; margin-bottom: 30px; color: #666; }
        </style>
      </head>
      <body>
        <div class="header">
          <div class="container">
            <div class="nav">
              <h1>CrystalGigs</h1>
              <div>
                <a href="/post" class="btn btn-post">Post a Job ($99)</a>
                <a href="/api/v1/jobs" class="btn">API</a>
              </div>
            </div>
          </div>
        </div>
        
        <div class="container">
          <div class="hero">
            <h2>Find Your Next Crystal Developer Role</h2>
            <p>The premier job board for Crystal language opportunities</p>
          </div>
          
          #{jobs.size > 0 ? %(<div class="stats">#{jobs.size} active job#{jobs.size == 1 ? "" : "s"} available</div>) : ""}
          
          <div class="jobs">
            #{jobs_html}
          </div>
          
          #{jobs.size > 0 ? %(<p style="text-align: center; color: #666; margin-top: 40px;">Ready to hire Crystal developers? <a href="/post">Post your job</a> for $99.</p>) : ""}
        </div>
      </body>
      </html>
      HTML
      
    rescue ex : Exception
      puts "Homepage error: #{ex.message}"
      # Fallback to basic HTML if database fails
      <<-HTML
      <!DOCTYPE html>
      <html>
      <head>
        <title>CrystalGigs - Crystal Developer Jobs</title>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 0; background: #f8f9fa; text-align: center; padding: 100px 20px; }
          .btn { background: #28a745; color: white; padding: 15px 30px; text-decoration: none; border-radius: 4px; display: inline-block; }
        </style>
      </head>
      <body>
        <h1>CrystalGigs</h1>
        <h2>Crystal Developer Jobs</h2>
        <p>Database temporarily unavailable. Please try again later.</p>
        <a href="/post" class="btn">Post a Job</a>
      </body>
      </html>
      HTML
    end
  end
  
  # Job posting form
  get "/post" do |env|
    error_message = case env.params.query["error"]?
    when "payment_cancelled"
      "Payment was cancelled. Please try again."
    when "payment_failed"
      "Payment failed. Please check your payment details and try again."
    when "job_data_expired"
      "Your session expired. Please fill out the form again."
    when "database_error"
      "There was an error saving your job. Please contact support."
    when "processing_error"
      "There was an error processing your request. Please try again."
    else
      nil
    end
    
    error_html = error_message ? %(<div style="background: #f8d7da; color: #721c24; padding: 15px; border-radius: 4px; margin-bottom: 20px;">#{error_message}</div>) : ""
    
    <<-HTML
    <!DOCTYPE html>
    <html>
    <head>
      <title>Post a Job - CrystalGigs</title>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 0; background: #f8f9fa; }
        .header { background: white; padding: 20px; border-bottom: 1px solid #ddd; }
        .container { max-width: 800px; margin: 0 auto; padding: 20px; }
        .form-group { margin-bottom: 20px; }
        label { display: block; margin-bottom: 5px; font-weight: 600; }
        input, textarea, select { width: 100%; padding: 10px; border: 1px solid #ddd; border-radius: 4px; font-size: 16px; }
        textarea { height: 120px; resize: vertical; }
        .btn { background: #28a745; color: white; padding: 15px 30px; border: none; border-radius: 4px; font-size: 16px; cursor: pointer; }
        .pricing { background: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
        .price { font-size: 24px; font-weight: 600; color: #28a745; }
      </style>
    </head>
    <body>
      <div class="header">
        <div class="container">
          <h1><a href="/" style="text-decoration: none; color: inherit;">CrystalGigs</a></h1>
        </div>
      </div>
      
      <div class="container">
        <h2>Post a Crystal Developer Job</h2>
        
        #{error_html}
        
        <div class="pricing">
          <div class="price">$99 for 30 days</div>
          <p>Your job will be featured on CrystalGigs.com and promoted to our newsletter subscribers.</p>
        </div>
        
        <form action="/jobs" method="post">
          <div class="form-group">
            <label>Job Title *</label>
            <input type="text" name="title" required placeholder="e.g. Senior Crystal Developer">
          </div>
          
          <div class="form-group">
            <label>Company Name *</label>
            <input type="text" name="company" required placeholder="Your Company">
          </div>
          
          <div class="form-group">
            <label>Location *</label>
            <input type="text" name="location" required placeholder="e.g. Remote, San Francisco, CA">
          </div>
          
          <div class="form-group">
            <label>Job Type *</label>
            <select name="type" required>
              <option value="">Select...</option>
              <option value="full-time">Full Time</option>
              <option value="part-time">Part Time</option>
              <option value="contract">Contract</option>
              <option value="freelance">Freelance</option>
            </select>
          </div>
          
          <div class="form-group">
            <label>Salary Range</label>
            <input type="text" name="salary" placeholder="e.g. $120k - $160k, Competitive">
          </div>
          
          <div class="form-group">
            <label>Job Description *</label>
            <textarea name="description" required placeholder="Describe the role, requirements, and what makes your company great..."></textarea>
          </div>
          
          <div class="form-group">
            <label>Application Email *</label>
            <input type="email" name="email" required placeholder="jobs@yourcompany.com">
          </div>
          
          <div class="form-group">
            <label>Company Website</label>
            <input type="url" name="website" placeholder="https://yourcompany.com">
          </div>
          
          <button type="submit" class="btn">Post Job - $99</button>
        </form>
      </div>
    </body>
    </html>
    HTML
  end
  
  # Handle job submission
  post "/jobs" do |env|
    begin
      # Extract job data from form
      job_data = {
        "title" => env.params.body["title"]?.to_s,
        "company" => env.params.body["company"]?.to_s,
        "location" => env.params.body["location"]?.to_s,
        "type" => env.params.body["type"]?.to_s,
        "salary" => env.params.body["salary"]?.to_s,
        "description" => env.params.body["description"]?.to_s,
        "email" => env.params.body["email"]?.to_s,
        "website" => env.params.body["website"]?.to_s
      }
      
      # Validate required fields
      required_fields = ["title", "company", "location", "type", "description", "email"]
      missing_fields = required_fields.select { |field| job_data[field].empty? }
      
      if !missing_fields.empty?
        env.response.status_code = 400
        next "Error: Missing required fields: #{missing_fields.join(", ")}"
      end
      
      # Store job data in Redis temporarily (for 1 hour)
      job_key = "job_draft_#{Time.utc.to_unix_ms}"
      REDIS.setex(job_key, 3600, job_data.to_json)
      
      # Create Stripe checkout session
      base_url = "#{env.request.scheme}://#{env.request.host_with_port}"
      success_url = "#{base_url}/payment/success?session_id={CHECKOUT_SESSION_ID}&job_key=#{job_key}"
      cancel_url = "#{base_url}/post?error=payment_cancelled"
      
      checkout_result = StripeService.create_checkout_session(job_data, success_url, cancel_url)
      
      if checkout_result.nil?
        env.response.status_code = 500
        next "Error: Could not create payment session. Please try again."
      end
      
      # Redirect to Stripe Checkout
      env.redirect checkout_result[:checkout_url]
      
    rescue ex : Exception
      puts "Error processing job submission: #{ex.message}"
      env.response.status_code = 500
      "Error: Could not process your job posting. Please try again."
    end
  end
  
  # Payment success page
  get "/payment/success" do |env|
    begin
      session_id = env.params.query["session_id"]?
      job_key = env.params.query["job_key"]?
      
      if !session_id || !job_key
        env.redirect "/post?error=invalid_payment"
        next
      end
      
      # Verify payment with Stripe
      session = StripeService.retrieve_session(session_id)
      if !session || session.payment_status != "paid"
        env.redirect "/post?error=payment_failed"
        next
      end
      
      # Get job data from Redis
      job_data_json = REDIS.get(job_key)
      if !job_data_json
        env.redirect "/post?error=job_data_expired"
        next
      end
      
      job_data = JSON.parse(job_data_json).as_h.transform_values(&.as_s)
      
      # Create job posting in database
      job_result = JobRepository.create_job(job_data, session_id)
      if !job_result
        env.redirect "/post?error=database_error"
        next
      end
      
      # Clean up Redis
      REDIS.del(job_key)
      
      <<-HTML
      <!DOCTYPE html>
      <html>
      <head>
        <title>Payment Success - CrystalGigs</title>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 0; background: #f8f9fa; }
          .container { max-width: 600px; margin: 100px auto; padding: 40px; background: white; border-radius: 8px; text-align: center; }
          .success { color: #28a745; font-size: 48px; margin-bottom: 20px; }
          .btn { background: #007bff; color: white; padding: 15px 30px; text-decoration: none; border-radius: 4px; display: inline-block; margin-top: 20px; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="success">✓</div>
          <h2>Payment Successful!</h2>
          <p><strong>Thank you for your payment!</strong></p>
          <p>Your job posting "<strong>#{job_data["title"]}</strong>" at <strong>#{job_data["company"]}</strong> has been submitted successfully.</p>
          <p>Your job will be:</p>
          <ul style="text-align: left; display: inline-block;">
            <li>Live on CrystalGigs.com for 30 days</li>
            <li>Featured in our job listings</li>
            <li>Promoted to our newsletter subscribers</li>
          </ul>
          <p><strong>Job ID:</strong> ##{job_result[:id]}</p>
          <p>You can view your job posting once it goes live (usually within 1 hour).</p>
          <a href="/" class="btn">View All Jobs</a>
        </div>
      </body>
      </html>
      HTML
      
    rescue ex : Exception
      puts "Error in payment success: #{ex.message}"
      env.redirect "/post?error=processing_error"
    end
  end
  
  # Stripe webhook handler
  post "/webhook/stripe" do |env|
    begin
      payload = env.request.body.not_nil!.gets_to_end
      sig_header = env.request.headers["Stripe-Signature"]?
      
      # For now, we'll trust the webhook since we're using checkout sessions
      # In production, you should verify the webhook signature
      
      event = JSON.parse(payload)
      
      case event["type"]
      when "checkout.session.completed"
        session_data = event["data"]["object"]
        session_id = session_data["id"].as_s
        
        puts "Webhook: Checkout session completed - #{session_id}"
        
        # Additional webhook processing can be added here
        # The main job creation is handled in the success page
        
      when "payment_intent.succeeded"
        payment_intent = event["data"]["object"]
        puts "Webhook: Payment succeeded - #{payment_intent["id"]}"
      end
      
      env.response.status_code = 200
      {status: "received"}.to_json
      
    rescue ex : Exception
      puts "Webhook error: #{ex.message}"
      env.response.status_code = 400
      {error: "Invalid webhook"}.to_json
    end
  end
  
  # API endpoints for jobs
  get "/api/v1/jobs" do |env|
    env.response.content_type = "application/json"
    
    begin
      # Get query parameters
      limit = (env.params.query["limit"]?.try(&.to_i) || 20).clamp(1, 100)
      offset = (env.params.query["offset"]?.try(&.to_i) || 0).clamp(0, Int32::MAX)
      query = env.params.query["q"]?.to_s
      
      # Search or get all jobs
      jobs = if !query.empty?
        JobRepository.search_jobs(query, limit, offset)
      else
        JobRepository.get_all_jobs(approved_only: true, limit: limit, offset: offset)
      end
      
      {
        jobs: jobs,
        total: jobs.size,
        page: (offset / limit) + 1,
        per_page: limit,
        query: query
      }.to_json
      
    rescue ex : Exception
      puts "API error: #{ex.message}"
      env.response.status_code = 500
      {error: "Internal server error"}.to_json
    end
  end
  
  # CORS middleware
  before_all do |env|
    env.response.headers["Access-Control-Allow-Origin"] = "*"
    env.response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
    env.response.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
  end
  
  # Handle OPTIONS requests
  options "/*" do |env|
    env.response.status_code = 200
  end
  
  # Error handlers
  error 404 do |env|
    env.response.content_type = "text/html"
    <<-HTML
    <!DOCTYPE html>
    <html>
    <head><title>Not Found - CrystalGigs</title></head>
    <body style="font-family: sans-serif; text-align: center; margin-top: 100px;">
      <h1>404 - Page Not Found</h1>
      <p><a href="/">Back to Jobs</a></p>
    </body>
    </html>
    HTML
  end
end

# Start the server
port = ENV["PORT"]?.try(&.to_i) || 3002
puts "Starting CrystalGigs on port #{port}"
Kemal.run(port)