require "crypto/bcrypt/password"
require "secure_random"
require "jwt"
require "time"

# User model with authentication
class User
  DB.mapping({
    id: Int32,
    email: String,
    name: String,
    github_username: String?,
    avatar_url: String?,
    bio: String?,
    website: String?,
    admin: Bool,
    email_verified: Bool,
    password_hash: String?,
    password_reset_token: String?,
    password_reset_expires: Time?,
    email_verification_token: String?,
    email_verification_expires: Time?,
    last_login: Time?,
    created_at: Time,
    updated_at: Time,
  })

  def self.create_with_password(email : String, name : String, password : String)
    password_hash = Crypto::Bcrypt::Password.create(password).to_s
    
    # Generate email verification token
    verification_token = SecureRandom.urlsafe_base64(32)
    verification_expires = Time.utc + 24.hours

    db = Database.get_connection
    user_id = db.scalar(
      "INSERT INTO users (email, name, password_hash, email_verification_token, email_verification_expires) 
       VALUES ($1, $2, $3, $4, $5) RETURNING id",
      email, name, password_hash, verification_token, verification_expires
    ).as(Int32)

    find(user_id)
  end

  def self.authenticate(email : String, password : String) : User?
    db = Database.get_connection
    user = db.query_one?(
      "SELECT * FROM users WHERE email = $1 AND password_hash IS NOT NULL",
      email,
      as: User
    )

    return nil unless user
    return nil unless user.password_hash

    if Crypto::Bcrypt::Password.new(user.password_hash.not_nil!).verify(password)
      # Update last login
      db.exec("UPDATE users SET last_login = NOW() WHERE id = $1", user.id)
      user
    else
      nil
    end
  end

  def self.find_by_email(email : String) : User?
    db = Database.get_connection
    db.query_one?("SELECT * FROM users WHERE email = $1", email, as: User)
  end

  def self.find(id : Int32) : User?
    db = Database.get_connection
    db.query_one?("SELECT * FROM users WHERE id = $1", id, as: User)
  end

  def update_password(new_password : String)
    password_hash = Crypto::Bcrypt::Password.create(new_password).to_s
    db = Database.get_connection
    db.exec(
      "UPDATE users SET password_hash = $1, password_reset_token = NULL, password_reset_expires = NULL 
       WHERE id = $2",
      password_hash, id
    )
  end

  def generate_password_reset_token
    token = SecureRandom.urlsafe_base64(32)
    expires = Time.utc + 1.hour
    
    db = Database.get_connection
    db.exec(
      "UPDATE users SET password_reset_token = $1, password_reset_expires = $2 WHERE id = $3",
      token, expires, id
    )
    token
  end

  def verify_email
    db = Database.get_connection
    db.exec(
      "UPDATE users SET email_verified = TRUE, email_verification_token = NULL, 
       email_verification_expires = NULL WHERE id = $1",
      id
    )
  end
end

# API Key model for API authentication
class ApiKey
  DB.mapping({
    id: Int32,
    user_id: Int32,
    key_hash: String,
    name: String,
    scopes: Array(String),
    last_used: Time?,
    expires_at: Time?,
    created_at: Time,
    updated_at: Time,
  })

  def self.create_for_user(user_id : Int32, name : String, scopes : Array(String) = [] of String, expires_at : Time? = nil)
    # Generate random API key
    key = "cs_#{SecureRandom.hex(32)}"
    key_hash = Crypto::Bcrypt::Password.create(key).to_s

    db = Database.get_connection
    api_key_id = db.scalar(
      "INSERT INTO api_keys (user_id, key_hash, name, scopes, expires_at) 
       VALUES ($1, $2, $3, $4, $5) RETURNING id",
      user_id, key_hash, name, scopes, expires_at
    ).as(Int32)

    api_key = find(api_key_id)
    {key: key, api_key: api_key}
  end

  def self.authenticate(key : String) : ApiKey?
    return nil unless key.starts_with?("cs_")
    
    db = Database.get_connection
    api_keys = db.query_all("SELECT * FROM api_keys WHERE expires_at IS NULL OR expires_at > NOW()", as: ApiKey)
    
    api_keys.each do |api_key|
      if Crypto::Bcrypt::Password.new(api_key.key_hash).verify(key)
        # Update last used
        db.exec("UPDATE api_keys SET last_used = NOW() WHERE id = $1", api_key.id)
        return api_key
      end
    end
    
    nil
  end

  def self.find(id : Int32) : ApiKey?
    db = Database.get_connection
    db.query_one?("SELECT * FROM api_keys WHERE id = $1", id, as: ApiKey)
  end

  def user
    User.find(user_id)
  end
end

# User Session model for web authentication
class UserSession
  DB.mapping({
    id: Int32,
    user_id: Int32,
    session_token: String,
    csrf_token: String,
    user_agent: String?,
    ip_address: String?,
    expires_at: Time,
    created_at: Time,
    updated_at: Time,
  })

  def self.create_for_user(user_id : Int32, user_agent : String? = nil, ip_address : String? = nil)
    session_token = SecureRandom.urlsafe_base64(32)
    csrf_token = SecureRandom.urlsafe_base64(32)
    expires_at = Time.utc + 30.days

    db = Database.get_connection
    session_id = db.scalar(
      "INSERT INTO user_sessions (user_id, session_token, csrf_token, user_agent, ip_address, expires_at) 
       VALUES ($1, $2, $3, $4, $5, $6) RETURNING id",
      user_id, session_token, csrf_token, user_agent, ip_address, expires_at
    ).as(Int32)

    find(session_id)
  end

  def self.authenticate(session_token : String) : UserSession?
    db = Database.get_connection
    db.query_one?(
      "SELECT * FROM user_sessions WHERE session_token = $1 AND expires_at > NOW()",
      session_token,
      as: UserSession
    )
  end

  def self.find(id : Int32) : UserSession?
    db = Database.get_connection
    db.query_one?("SELECT * FROM user_sessions WHERE id = $1", id, as: UserSession)
  end

  def user
    User.find(user_id)
  end

  def destroy
    db = Database.get_connection
    db.exec("DELETE FROM user_sessions WHERE id = $1", id)
  end

  def extend_expiration
    new_expires = Time.utc + 30.days
    db = Database.get_connection
    db.exec("UPDATE user_sessions SET expires_at = $1 WHERE id = $2", new_expires, id)
  end
end

# OAuth Provider model for GitHub/Google authentication
class OAuthProvider
  DB.mapping({
    id: Int32,
    user_id: Int32,
    provider: String,
    provider_user_id: String,
    access_token: String?,
    refresh_token: String?,
    expires_at: Time?,
    created_at: Time,
    updated_at: Time,
  })

  def self.find_or_create_user_from_github(github_user_id : String, email : String, name : String, avatar_url : String?, access_token : String)
    db = Database.get_connection

    # First try to find existing OAuth connection
    oauth = db.query_one?(
      "SELECT * FROM oauth_providers WHERE provider = 'github' AND provider_user_id = $1",
      github_user_id, as: OAuthProvider
    )

    if oauth
      # Update tokens
      db.exec(
        "UPDATE oauth_providers SET access_token = $1, updated_at = NOW() WHERE id = $2",
        access_token, oauth.id
      )
      return oauth.user
    end

    # Try to find user by email
    user = User.find_by_email(email)
    
    if user
      # Link existing user to GitHub
      oauth_id = db.scalar(
        "INSERT INTO oauth_providers (user_id, provider, provider_user_id, access_token) 
         VALUES ($1, 'github', $2, $3) RETURNING id",
        user.id, github_user_id, access_token
      ).as(Int32)
    else
      # Create new user
      user_id = db.scalar(
        "INSERT INTO users (email, name, github_username, avatar_url, email_verified) 
         VALUES ($1, $2, $3, $4, TRUE) RETURNING id",
        email, name, github_user_id, avatar_url
      ).as(Int32)

      # Create OAuth connection
      oauth_id = db.scalar(
        "INSERT INTO oauth_providers (user_id, provider, provider_user_id, access_token) 
         VALUES ($1, 'github', $2, $3) RETURNING id",
        user_id, github_user_id, access_token
      ).as(Int32)

      user = User.find(user_id)
    end

    user
  end

  def user
    User.find(user_id)
  end
end

# JWT Token utilities
module JWTAuth
  SECRET_KEY = ENV.fetch("JWT_SECRET", "development_secret_key_change_in_production")

  def self.encode(payload : Hash(String, JSON::Any::Type), expiration : Time = Time.utc + 1.hour)
    payload["exp"] = expiration.to_unix.to_i64
    payload["iat"] = Time.utc.to_unix.to_i64
    JWT.encode(payload, SECRET_KEY, JWT::Algorithm::HS256)
  end

  def self.decode(token : String)
    payload, header = JWT.decode(token, SECRET_KEY, JWT::Algorithm::HS256)
    payload
  rescue JWT::DecodeError
    nil
  end

  def self.create_access_token(user : User)
    payload = {
      "user_id" => user.id,
      "email" => user.email,
      "admin" => user.admin,
      "type" => "access"
    }.transform_values(&.as(JSON::Any::Type))

    encode(payload, Time.utc + 1.hour)
  end

  def self.create_refresh_token(user : User)
    payload = {
      "user_id" => user.id,
      "type" => "refresh"
    }.transform_values(&.as(JSON::Any::Type))

    encode(payload, Time.utc + 30.days)
  end

  def self.verify_access_token(token : String) : User?
    payload = decode(token)
    return nil unless payload
    return nil unless payload["type"]?.as(String?) == "access"

    user_id = payload["user_id"]?.as(Int64?)
    return nil unless user_id

    User.find(user_id.to_i32)
  end

  def self.verify_refresh_token(token : String) : User?
    payload = decode(token)
    return nil unless payload
    return nil unless payload["type"]?.as(String?) == "refresh"

    user_id = payload["user_id"]?.as(Int64?)
    return nil unless user_id

    User.find(user_id.to_i32)
  end
end