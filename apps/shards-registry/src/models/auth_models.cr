require "crypto/bcrypt/password"
require "secure_random"
require "jwt"
require "time"

module CrystalShards
  # Simple User authentication methods for the existing user system
  class UserAuth
    def self.create_with_password(db : PG::Connection, email : String, name : String, password : String)
      password_hash = Crypto::Bcrypt::Password.create(password).to_s
      
      # Generate email verification token
      verification_token = SecureRandom.urlsafe_base64(32)
      verification_expires = Time.utc + 24.hours

      user_id = db.scalar(
        "INSERT INTO users (email, name, password_hash, email_verification_token, email_verification_expires) 
         VALUES ($1, $2, $3, $4, $5) RETURNING id",
        email, name, password_hash, verification_token, verification_expires
      ).as(Int32)

      find(db, user_id)
    end

    def self.authenticate(db : PG::Connection, email : String, password : String)
      result = db.query_one?(
        "SELECT id, email, name, github_username, avatar_url, bio, website, admin, email_verified, password_hash, last_login, created_at, updated_at 
         FROM users WHERE email = $1 AND password_hash IS NOT NULL",
        email
      )

      return nil unless result

      user_id = result[0].as(Int32)
      user_email = result[1].as(String)
      user_name = result[2].as(String)
      github_username = result[3].as(String?)
      avatar_url = result[4].as(String?)
      bio = result[5].as(String?)
      website = result[6].as(String?)
      admin = result[7].as(Bool)
      email_verified = result[8].as(Bool)
      password_hash = result[9].as(String?)
      last_login = result[10].as(Time?)
      created_at = result[11].as(Time)
      updated_at = result[12].as(Time)

      return nil unless password_hash

      if Crypto::Bcrypt::Password.new(password_hash).verify(password)
        # Update last login
        db.exec("UPDATE users SET last_login = NOW() WHERE id = $1", user_id)
        
        AuthenticatedUser.new(
          id: user_id,
          email: user_email,
          name: user_name,
          github_username: github_username,
          avatar_url: avatar_url,
          bio: bio,
          website: website,
          admin: admin,
          email_verified: email_verified,
          last_login: Time.utc,
          created_at: created_at,
          updated_at: updated_at
        )
      else
        nil
      end
    end

    def self.find_by_email(db : PG::Connection, email : String)
      result = db.query_one?(
        "SELECT id, email, name, github_username, avatar_url, bio, website, admin, email_verified, last_login, created_at, updated_at 
         FROM users WHERE email = $1", 
        email
      )
      return nil unless result

      AuthenticatedUser.new(
        id: result[0].as(Int32),
        email: result[1].as(String),
        name: result[2].as(String),
        github_username: result[3].as(String?),
        avatar_url: result[4].as(String?),
        bio: result[5].as(String?),
        website: result[6].as(String?),
        admin: result[7].as(Bool),
        email_verified: result[8].as(Bool),
        last_login: result[9].as(Time?),
        created_at: result[10].as(Time),
        updated_at: result[11].as(Time)
      )
    end

    def self.find(db : PG::Connection, id : Int32)
      result = db.query_one?(
        "SELECT id, email, name, github_username, avatar_url, bio, website, admin, email_verified, last_login, created_at, updated_at 
         FROM users WHERE id = $1", 
        id
      )
      return nil unless result

      AuthenticatedUser.new(
        id: result[0].as(Int32),
        email: result[1].as(String),
        name: result[2].as(String),
        github_username: result[3].as(String?),
        avatar_url: result[4].as(String?),
        bio: result[5].as(String?),
        website: result[6].as(String?),
        admin: result[7].as(Bool),
        email_verified: result[8].as(Bool),
        last_login: result[9].as(Time?),
        created_at: result[10].as(Time),
        updated_at: result[11].as(Time)
      )
    end
  end

  # Simple authenticated user struct
  struct AuthenticatedUser
    include JSON::Serializable
    
    property id : Int32
    property email : String
    property name : String
    property github_username : String?
    property avatar_url : String?
    property bio : String?
    property website : String?
    property admin : Bool
    property email_verified : Bool
    property last_login : Time?
    property created_at : Time
    property updated_at : Time

    def initialize(@id : Int32, @email : String, @name : String, @github_username : String?, @avatar_url : String?, @bio : String?, @website : String?, @admin : Bool, @email_verified : Bool, @last_login : Time?, @created_at : Time, @updated_at : Time)
    end
  end

  # API Key authentication
  class ApiKeyAuth
    def self.create_for_user(db : PG::Connection, user_id : Int32, name : String, scopes : Array(String) = [] of String, expires_at : Time? = nil)
      # Generate random API key
      key = "cs_#{SecureRandom.hex(32)}"
      key_hash = Crypto::Bcrypt::Password.create(key).to_s

      api_key_id = db.scalar(
        "INSERT INTO api_keys (user_id, key_hash, name, scopes, expires_at) 
         VALUES ($1, $2, $3, $4, $5) RETURNING id",
        user_id, key_hash, name, scopes, expires_at
      ).as(Int32)

      api_key = find(db, api_key_id)
      {key: key, api_key: api_key}
    end

    def self.authenticate(db : PG::Connection, key : String)
      return nil unless key.starts_with?("cs_")
      
      results = db.query_all(
        "SELECT id, user_id, key_hash, name, scopes, last_used, expires_at, created_at, updated_at 
         FROM api_keys WHERE expires_at IS NULL OR expires_at > NOW()"
      )
      
      results.each do |result|
        api_key_id = result[0].as(Int32)
        user_id = result[1].as(Int32)
        key_hash = result[2].as(String)
        name = result[3].as(String)
        scopes = result[4].as(Array(String))
        last_used = result[5].as(Time?)
        expires_at = result[6].as(Time?)
        created_at = result[7].as(Time)
        updated_at = result[8].as(Time)
        
        if Crypto::Bcrypt::Password.new(key_hash).verify(key)
          # Update last used
          db.exec("UPDATE api_keys SET last_used = NOW() WHERE id = $1", api_key_id)
          
          return AuthenticatedApiKey.new(
            id: api_key_id,
            user_id: user_id,
            name: name,
            scopes: scopes,
            last_used: Time.utc,
            expires_at: expires_at,
            created_at: created_at,
            updated_at: updated_at
          )
        end
      end
      
      nil
    end

    def self.find(db : PG::Connection, id : Int32)
      result = db.query_one?(
        "SELECT id, user_id, key_hash, name, scopes, last_used, expires_at, created_at, updated_at 
         FROM api_keys WHERE id = $1", 
        id
      )
      return nil unless result

      AuthenticatedApiKey.new(
        id: result[0].as(Int32),
        user_id: result[1].as(Int32),
        name: result[3].as(String),
        scopes: result[4].as(Array(String)),
        last_used: result[5].as(Time?),
        expires_at: result[6].as(Time?),
        created_at: result[7].as(Time),
        updated_at: result[8].as(Time)
      )
    end
  end

  struct AuthenticatedApiKey
    include JSON::Serializable
    
    property id : Int32
    property user_id : Int32
    property name : String
    property scopes : Array(String)
    property last_used : Time?
    property expires_at : Time?
    property created_at : Time
    property updated_at : Time

    def initialize(@id : Int32, @user_id : Int32, @name : String, @scopes : Array(String), @last_used : Time?, @expires_at : Time?, @created_at : Time, @updated_at : Time)
    end

    def user(db : PG::Connection)
      UserAuth.find(db, user_id)
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

    def self.create_access_token(user : AuthenticatedUser)
      payload = {
        "user_id" => user.id.to_i64,
        "email" => user.email,
        "admin" => user.admin,
        "type" => "access"
      }.transform_values(&.as(JSON::Any::Type))

      encode(payload, Time.utc + 1.hour)
    end

    def self.create_refresh_token(user : AuthenticatedUser)
      payload = {
        "user_id" => user.id.to_i64,
        "type" => "refresh"
      }.transform_values(&.as(JSON::Any::Type))

      encode(payload, Time.utc + 30.days)
    end

    def self.verify_access_token(db : PG::Connection, token : String) : AuthenticatedUser?
      payload = decode(token)
      return nil unless payload
      return nil unless payload["type"]?.as(String?) == "access"

      user_id = payload["user_id"]?.as(Int64?)
      return nil unless user_id

      UserAuth.find(db, user_id.to_i32)
    end

    def self.verify_refresh_token(db : PG::Connection, token : String) : AuthenticatedUser?
      payload = decode(token)
      return nil unless payload
      return nil unless payload["type"]?.as(String?) == "refresh"

      user_id = payload["user_id"]?.as(Int64?)
      return nil unless user_id

      UserAuth.find(db, user_id.to_i32)
    end
  end
end