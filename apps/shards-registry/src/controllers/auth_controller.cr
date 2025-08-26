require "kemal"
require "json"
require "../models/auth_models"

module CrystalShards
  # User registration endpoint
  post "/api/auth/register" do |env|
    env.response.content_type = "application/json"
    
    begin
      body = env.request.body
      raise "Missing request body" unless body
      
      data = JSON.parse(body.gets_to_end)
      email = data["email"]?.as(String?)
      name = data["name"]?.as(String?)
      password = data["password"]?.as(String?)
      
      raise "Email is required" unless email
      raise "Name is required" unless name
      raise "Password is required" unless password
      raise "Password must be at least 8 characters" if password.size < 8
      raise "Invalid email format" unless email.includes?("@")
      
      # Check if user already exists
      if UserAuth.find_by_email(DB, email)
        env.response.status_code = 400
        next {error: "User with this email already exists"}.to_json
      end
      
      # Create user
      user = UserAuth.create_with_password(DB, email, name, password)
      next {error: "Failed to create user"}.to_json unless user
      
      # Generate tokens
      access_token = JWTAuth.create_access_token(user)
      refresh_token = JWTAuth.create_refresh_token(user)
      
      {
        success: true,
        message: "User created successfully",
        user: {
          id: user.id,
          email: user.email,
          name: user.name,
          email_verified: user.email_verified
        },
        tokens: {
          access_token: access_token,
          refresh_token: refresh_token
        }
      }.to_json
      
    rescue ex
      env.response.status_code = 400
      {error: ex.message}.to_json
    end
  end
  
  # User login endpoint
  post "/api/auth/login" do |env|
    env.response.content_type = "application/json"
    
    begin
      body = env.request.body
      raise "Missing request body" unless body
      
      data = JSON.parse(body.gets_to_end)
      email = data["email"]?.as(String?)
      password = data["password"]?.as(String?)
      
      raise "Email is required" unless email
      raise "Password is required" unless password
      
      # Authenticate user
      user = UserAuth.authenticate(DB, email, password)
      unless user
        env.response.status_code = 401
        next {error: "Invalid email or password"}.to_json
      end
      
      # Generate tokens
      access_token = JWTAuth.create_access_token(user)
      refresh_token = JWTAuth.create_refresh_token(user)
      
      {
        success: true,
        message: "Login successful",
        user: {
          id: user.id,
          email: user.email,
          name: user.name,
          email_verified: user.email_verified,
          admin: user.admin
        },
        tokens: {
          access_token: access_token,
          refresh_token: refresh_token
        }
      }.to_json
      
    rescue ex
      env.response.status_code = 400
      {error: ex.message}.to_json
    end
  end
  
  # Token refresh endpoint
  post "/api/auth/refresh" do |env|
    env.response.content_type = "application/json"
    
    begin
      body = env.request.body
      raise "Missing request body" unless body
      
      data = JSON.parse(body.gets_to_end)
      refresh_token = data["refresh_token"]?.as(String?)
      
      raise "Refresh token is required" unless refresh_token
      
      # Verify refresh token
      user = JWTAuth.verify_refresh_token(DB, refresh_token)
      unless user
        env.response.status_code = 401
        next {error: "Invalid or expired refresh token"}.to_json
      end
      
      # Generate new access token
      new_access_token = JWTAuth.create_access_token(user)
      
      {
        success: true,
        tokens: {
          access_token: new_access_token
        }
      }.to_json
      
    rescue ex
      env.response.status_code = 400
      {error: ex.message}.to_json
    end
  end
  
  # Get current user info
  get "/api/auth/me" do |env|
    env.response.content_type = "application/json"
    
    user = env.get?("current_user").as(AuthenticatedUser?)
    unless user
      env.response.status_code = 401
      next {error: "Authentication required"}.to_json
    end
    
    {
      success: true,
      user: {
        id: user.id,
        email: user.email,
        name: user.name,
        github_username: user.github_username,
        avatar_url: user.avatar_url,
        bio: user.bio,
        website: user.website,
        admin: user.admin,
        email_verified: user.email_verified,
        last_login: user.last_login,
        created_at: user.created_at
      }
    }.to_json
  end
  
  # Create API key
  post "/api/auth/api-keys" do |env|
    env.response.content_type = "application/json"
    
    user = env.get?("current_user").as(AuthenticatedUser?)
    unless user
      env.response.status_code = 401
      next {error: "Authentication required"}.to_json
    end
    
    begin
      body = env.request.body
      raise "Missing request body" unless body
      
      data = JSON.parse(body.gets_to_end)
      name = data["name"]?.as(String?)
      scopes_array = data["scopes"]?.as(Array(JSON::Any)?)
      scopes = scopes_array ? scopes_array.map(&.as(String)) : ["read"]
      
      raise "Name is required" unless name
      
      # Create API key
      result = ApiKeyAuth.create_for_user(DB, user.id, name, scopes)
      api_key = result[:api_key]
      key = result[:key]
      
      {
        success: true,
        message: "API key created successfully",
        api_key: {
          id: api_key.try(&.id),
          name: api_key.try(&.name),
          key: key,  # Only show the key once
          scopes: api_key.try(&.scopes) || [] of String,
          created_at: api_key.try(&.created_at)
        }
      }.to_json
      
    rescue ex
      env.response.status_code = 400
      {error: ex.message}.to_json
    end
  end
end