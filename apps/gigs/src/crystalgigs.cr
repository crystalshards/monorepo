require "kemal"
require "pg"
require "redis"
require "jwt"
require "stripe"
require "cr-dotenv"

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
  
  # Health check endpoint
  get "/health" do |env|
    env.response.content_type = "application/json"
    {
      status: "ok",
      version: VERSION,
      timestamp: Time.utc.to_s
    }.to_json
  end
  
  # Job board homepage
  get "/" do |env|
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
        .job-company { color: #666; margin-bottom: 10px; }
        .job-location { color: #888; font-size: 14px; }
        .job-salary { color: #28a745; font-weight: 600; }
        .btn { background: #007bff; color: white; padding: 10px 20px; text-decoration: none; border-radius: 4px; display: inline-block; }
        .btn-post { background: #28a745; }
        .nav { display: flex; justify-content: space-between; align-items: center; }
      </style>
    </head>
    <body>
      <div class="header">
        <div class="container">
          <div class="nav">
            <h1>CrystalGigs</h1>
            <div>
              <a href="/post" class="btn btn-post">Post a Job ($99)</a>
              <a href="/login" class="btn">Login</a>
            </div>
          </div>
        </div>
      </div>
      
      <div class="container">
        <div class="hero">
          <h2>Find Your Next Crystal Developer Role</h2>
          <p>The premier job board for Crystal language opportunities</p>
        </div>
        
        <div class="jobs">
          <div class="job-card">
            <div class="job-title">Senior Crystal Developer</div>
            <div class="job-company">Example Company</div>
            <div class="job-location">Remote / San Francisco</div>
            <div class="job-salary">$120k - $160k</div>
            <p>We're looking for an experienced Crystal developer to join our backend team...</p>
          </div>
          
          <div class="job-card">
            <div class="job-title">Full Stack Crystal Engineer</div>
            <div class="job-company">StartupCo</div>
            <div class="job-location">New York, NY</div>
            <div class="job-salary">$90k - $130k + equity</div>
            <p>Join our fast-growing startup building high-performance web applications...</p>
          </div>
          
          <p style="text-align: center; color: #666; margin-top: 40px;">
            More jobs coming soon! <a href="/post">Post your job</a> to reach Crystal developers.
          </p>
        </div>
      </div>
    </body>
    </html>
    HTML
  end
  
  # Job posting form
  get "/post" do |env|
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
    # For now, just show success page
    # TODO: Integrate with Stripe for payment processing
    
    <<-HTML
    <!DOCTYPE html>
    <html>
    <head>
      <title>Payment - CrystalGigs</title>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <script src="https://js.stripe.com/v3/"></script>
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 0; background: #f8f9fa; }
        .container { max-width: 600px; margin: 100px auto; padding: 20px; background: white; border-radius: 8px; }
        .btn { background: #28a745; color: white; padding: 15px 30px; border: none; border-radius: 4px; font-size: 16px; cursor: pointer; width: 100%; }
      </style>
    </head>
    <body>
      <div class="container">
        <h2>Complete Your Payment</h2>
        <p>Job posting fee: <strong>$99</strong></p>
        <p>Your job will be live for 30 days once payment is processed.</p>
        
        <div id="card-element">
          <!-- Stripe Elements will create form elements here -->
        </div>
        
        <button id="submit-payment" class="btn">Pay $99</button>
        
        <p style="font-size: 14px; color: #666; margin-top: 20px;">
          Stripe integration will be implemented here for secure payment processing.
        </p>
      </div>
    </body>
    </html>
    HTML
  end
  
  # API endpoints for jobs
  get "/api/v1/jobs" do |env|
    env.response.content_type = "application/json"
    
    # Placeholder - will implement with database
    {
      jobs: [
        {
          id: 1,
          title: "Senior Crystal Developer",
          company: "Example Company",
          location: "Remote / San Francisco",
          salary: "$120k - $160k",
          type: "full-time",
          posted_at: "2025-08-26T00:00:00Z"
        }
      ],
      total: 1,
      page: 1,
      per_page: 20
    }.to_json
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