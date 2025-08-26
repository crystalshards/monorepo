require "redis"
require "json"

# Email preferences and unsubscribe management for CrystalShards platform
class EmailPreferences
  UNSUBSCRIBE_TTL = 86400 * 365 # 1 year

  def initialize(@redis : Redis)
  end

  # Email preference types
  enum PreferenceType
    JobConfirmations
    ShardNotifications
    DocsBuildNotifications
    MarketingEmails
    SecurityAlerts
    SystemUpdates
  end

  # Check if user has unsubscribed from a specific email type
  def unsubscribed?(email : String, preference_type : PreferenceType) : Bool
    key = "unsubscribe:#{preference_type.to_s.underscore}:#{email_hash(email)}"
    @redis.exists(key) == 1
  rescue
    false # Default to subscribed if Redis unavailable
  end

  # Unsubscribe user from specific email type
  def unsubscribe(email : String, preference_type : PreferenceType) : Bool
    key = "unsubscribe:#{preference_type.to_s.underscore}:#{email_hash(email)}"
    @redis.setex(key, UNSUBSCRIBE_TTL, Time.utc.to_unix.to_s)
    
    # Log unsubscribe event
    log_unsubscribe(email, preference_type)
    
    true
  rescue
    false
  end

  # Resubscribe user to specific email type
  def resubscribe(email : String, preference_type : PreferenceType) : Bool
    key = "unsubscribe:#{preference_type.to_s.underscore}:#{email_hash(email)}"
    @redis.del(key)
    true
  rescue
    false
  end

  # Get all preferences for a user
  def get_preferences(email : String) : Hash(String, Bool)
    preferences = {} of String => Bool
    
    PreferenceType.each do |type|
      preferences[type.to_s.underscore] = !unsubscribed?(email, type)
    end
    
    preferences
  end

  # Update multiple preferences at once
  def update_preferences(email : String, preferences : Hash(String, Bool)) : Bool
    preferences.each do |type_name, subscribed|
      begin
        type = PreferenceType.parse(type_name.camelcase)
        if subscribed
          resubscribe(email, type)
        else
          unsubscribe(email, type)
        end
      rescue ArgumentError
        # Skip invalid preference types
        next
      end
    end
    
    true
  end

  # Generate unsubscribe link for emails
  def generate_unsubscribe_link(email : String, preference_type : PreferenceType, base_url : String = "https://crystalshards.org") : String
    token = generate_unsubscribe_token(email, preference_type)
    "#{base_url}/unsubscribe?token=#{token}&type=#{preference_type.to_s.underscore}"
  end

  # Verify and process unsubscribe token
  def process_unsubscribe_token(token : String, preference_type : PreferenceType) : String?
    begin
      # Decode token to get email
      decoded = Base64.decode_string(token)
      parts = decoded.split(":")
      return nil if parts.size != 3
      
      email = parts[0]
      type_check = parts[1]
      timestamp = parts[2].to_i64
      
      # Verify token is for correct preference type and not expired
      return nil if type_check != preference_type.to_s.underscore
      return nil if Time.utc.to_unix - timestamp > 86400 * 7 # 7 day expiry
      
      # Verify token signature (simplified)
      expected_token = generate_unsubscribe_token(email, preference_type)
      return nil if token != expected_token
      
      # Process unsubscribe
      unsubscribe(email, preference_type)
      email
    rescue
      nil
    end
  end

  # Get unsubscribe statistics
  def get_unsubscribe_stats : Hash(String, Int64)
    stats = {} of String => Int64
    
    PreferenceType.each do |type|
      pattern = "unsubscribe:#{type.to_s.underscore}:*"
      keys = @redis.keys(pattern)
      stats[type.to_s.underscore] = keys.size.to_i64
    end
    
    stats["total"] = stats.values.sum
    stats
  rescue
    {} of String => Int64
  end

  # Check if email address is globally suppressed
  def globally_suppressed?(email : String) : Bool
    # Check bounce list, complaint list, etc.
    bounce_key = "bounce:#{email_hash(email)}"
    complaint_key = "complaint:#{email_hash(email)}"
    
    @redis.exists(bounce_key) == 1 || @redis.exists(complaint_key) == 1
  rescue
    false
  end

  # Add email to bounce list (hard bounces)
  def add_bounce(email : String, bounce_type : String = "hard") : Bool
    key = "bounce:#{email_hash(email)}"
    data = {
      "type" => bounce_type,
      "timestamp" => Time.utc.to_unix,
      "count" => get_bounce_count(email) + 1
    }
    
    @redis.setex(key, UNSUBSCRIBE_TTL, data.to_json)
    
    # Auto-unsubscribe from all emails after 3 hard bounces
    if data["count"].as(Int32) >= 3 && bounce_type == "hard"
      PreferenceType.each { |type| unsubscribe(email, type) }
    end
    
    true
  rescue
    false
  end

  # Add email to complaint list (spam reports)
  def add_complaint(email : String, complaint_type : String = "spam") : Bool
    key = "complaint:#{email_hash(email)}"
    data = {
      "type" => complaint_type,
      "timestamp" => Time.utc.to_unix
    }
    
    @redis.setex(key, UNSUBSCRIBE_TTL, data.to_json)
    
    # Auto-unsubscribe from all emails after any complaint
    PreferenceType.each { |type| unsubscribe(email, type) }
    
    true
  rescue
    false
  end

  private def email_hash(email : String) : String
    # Hash email for privacy (one-way)
    Digest::SHA256.hexdigest(email.downcase)[0..15]
  end

  private def generate_unsubscribe_token(email : String, preference_type : PreferenceType) : String
    # Generate secure token for unsubscribe links
    payload = "#{email}:#{preference_type.to_s.underscore}:#{Time.utc.to_unix}"
    Base64.encode_string(payload)
  end

  private def log_unsubscribe(email : String, preference_type : PreferenceType)
    # Log unsubscribe events for analytics (anonymized)
    key = "unsubscribe_log:#{Date.utc}"
    data = {
      "type" => preference_type.to_s.underscore,
      "timestamp" => Time.utc.to_unix,
      "email_hash" => email_hash(email)
    }
    
    @redis.lpush(key, data.to_json)
    @redis.expire(key, 86400 * 30) # Keep logs for 30 days
  rescue
    # Ignore logging failures
  end

  private def get_bounce_count(email : String) : Int32
    key = "bounce:#{email_hash(email)}"
    bounce_data = @redis.get(key)
    return 0 unless bounce_data
    
    data = JSON.parse(bounce_data)
    data["count"].as_i? || 0
  rescue
    0
  end
end

# Global email preferences instance
EMAIL_PREFERENCES = begin
  redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379")
  redis = Redis.new(URI.parse(redis_url))
  EmailPreferences.new(redis)
rescue
  puts "Warning: Email preferences Redis connection failed"
  nil
end