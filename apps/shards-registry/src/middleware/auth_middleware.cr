require "kemal"
require "../models/auth_models"

module CrystalShards
  # Authentication middleware for JWT token validation
  class AuthMiddleware < Kemal::Handler
    def call(env)
      # Skip authentication for public endpoints
      return call_next(env) if public_endpoint?(env.request.path)
      
      # Extract token from Authorization header
      auth_header = env.request.headers["Authorization"]?
      if auth_header && auth_header.starts_with?("Bearer ")
        token = auth_header[7..-1]
        
        # Verify JWT token
        if user = JWTAuth.verify_access_token(DB, token)
          env.set("current_user", user)
        end
      end
      
      # Check for API key authentication if no JWT token
      unless env.get?("current_user")
        api_key_header = env.request.headers["X-API-Key"]?
        if api_key_header
          if api_key = ApiKeyAuth.authenticate(DB, api_key_header)
            if api_user = api_key.user(DB)
              env.set("current_user", api_user)
              env.set("current_api_key", api_key)
            end
          end
        end
      end
      
      call_next(env)
    end
    
    private def public_endpoint?(path : String) : Bool
      public_paths = [
        "/",
        "/health",
        "/ready",
        "/metrics",
        "/api/shards",
        "/api/search",
        "/api/auth/register",
        "/api/auth/login",
        "/api/auth/refresh"
      ]
      
      # Allow GET requests to public API endpoints
      public_paths.any? { |public_path| path.starts_with?(public_path) } ||
      path.starts_with?("/api/shards/") && !path.includes?("/publish")
    end
  end
  
  # Helper method to require authentication
  def self.require_auth(env) : AuthenticatedUser?
    user = env.get?("current_user").as(AuthenticatedUser?)
    unless user
      env.response.status_code = 401
      env.response.content_type = "application/json"
      env.response.print({error: "Authentication required"}.to_json)
      return nil
    end
    user
  end
  
  # Helper method to require admin authentication
  def self.require_admin(env) : AuthenticatedUser?
    user = require_auth(env)
    return nil unless user
    
    unless user.admin
      env.response.status_code = 403
      env.response.content_type = "application/json"
      env.response.print({error: "Admin access required"}.to_json)
      return nil
    end
    user
  end
  
  # Helper method to check API key scope
  def self.check_api_scope(env, required_scope : String) : Bool
    api_key = env.get?("current_api_key").as(AuthenticatedApiKey?)
    return true unless api_key  # JWT auth doesn't have scopes
    
    api_key.scopes.includes?(required_scope) || api_key.scopes.includes?("admin")
  end
end