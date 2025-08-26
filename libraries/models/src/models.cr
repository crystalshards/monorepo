require "pg"
require "json"
require "./authentication"

module CrystalShared
  # Base model class with common functionality
  abstract class BaseModel
    include JSON::Serializable
    
    property created_at : Time?
    property updated_at : Time?
    
    def initialize
      now = Time.utc
      @created_at = now
      @updated_at = now
    end
    
    def touch
      @updated_at = Time.utc
    end
  end
  
  # Shard model representing a Crystal package
  class Shard < BaseModel
    include JSON::Serializable
    
    property id : Int32?
    property name : String
    property description : String?
    property github_url : String
    property homepage_url : String?
    property documentation_url : String?
    property license : String?
    property latest_version : String?
    property download_count : Int32
    property stars : Int32
    property forks : Int32
    property last_activity : Time?
    property tags : Array(String)
    property crystal_versions : Array(String)
    property dependencies : Hash(String, String)
    property published : Bool
    property featured : Bool
    
    def initialize(@name : String, @github_url : String)
      super()
      @download_count = 0
      @stars = 0
      @forks = 0
      @tags = [] of String
      @crystal_versions = [] of String
      @dependencies = {} of String => String
      @published = false
      @featured = false
    end
    
    def slug
      name.downcase.gsub(/[^a-z0-9\-]/, "-")
    end
    
    def github_owner_repo
      if match = github_url.match(/github\.com\/([^\/]+)\/([^\/]+)/)
        {match[1], match[2]}
      else
        {"", ""}
      end
    end
    
    def search_text
      [name, description, tags.join(" ")].compact.join(" ")
    end
  end
  
  # Version model for tracking shard versions
  class ShardVersion < BaseModel
    include JSON::Serializable
    
    property id : Int32?
    property shard_id : Int32
    property version : String
    property commit_sha : String?
    property release_notes : String?
    property yanked : Bool
    property prerelease : Bool
    property documentation_generated : Bool
    property download_count : Int32
    
    def initialize(@shard_id : Int32, @version : String)
      super()
      @yanked = false
      @prerelease = false
      @documentation_generated = false
      @download_count = 0
    end
    
    def semantic_version
      Version.parse(version)
    rescue
      nil
    end
  end
  
  # User model for authentication and authorization
  class User < BaseModel
    include JSON::Serializable
    
    property id : Int32?
    property email : String
    property name : String
    property github_username : String?
    property avatar_url : String?
    property bio : String?
    property website : String?
    property admin : Bool
    property email_verified : Bool
    property last_login : Time?
    
    def initialize(@email : String, @name : String)
      super()
      @admin = false
      @email_verified = false
    end
    
    def gravatar_url(size = 80)
      require "digest/md5"
      hash = Digest::MD5.hexdigest(email.downcase.strip)
      "https://www.gravatar.com/avatar/#{hash}?s=#{size}&d=identicon"
    end
  end
  
  # Job posting model for the job board
  class JobPosting < BaseModel
    include JSON::Serializable
    
    property id : Int32?
    property title : String
    property company : String
    property location : String
    property job_type : String  # full-time, part-time, contract, freelance
    property salary_range : String?
    property description : String
    property requirements : String?
    property application_email : String
    property company_website : String?
    property company_logo_url : String?
    property featured : Bool
    property approved : Bool
    property expires_at : Time
    property views : Int32
    property applications : Int32
    property stripe_payment_id : String?
    
    def initialize(@title : String, @company : String, @location : String, @job_type : String, @description : String, @application_email : String)
      super()
      @featured = false
      @approved = false
      @expires_at = Time.utc + 30.days
      @views = 0
      @applications = 0
    end
    
    def expired?
      Time.utc > expires_at
    end
    
    def slug
      title.downcase.gsub(/[^a-z0-9\-]/, "-") + "-at-" + company.downcase.gsub(/[^a-z0-9\-]/, "-")
    end
    
    def search_text
      [title, company, location, description, requirements].compact.join(" ")
    end
  end
  
  # Documentation model for tracking generated docs
  class Documentation < BaseModel
    include JSON::Serializable
    
    property id : Int32?
    property shard_id : Int32
    property version : String
    property content_path : String  # Path in MinIO storage
    property build_status : String  # pending, building, success, failed
    property build_log : String?
    property file_count : Int32
    property size_bytes : Int64
    
    def initialize(@shard_id : Int32, @version : String, @content_path : String)
      super()
      @build_status = "pending"
      @file_count = 0
      @size_bytes = 0_i64
    end
    
    def building?
      build_status == "building"
    end
    
    def success?
      build_status == "success"
    end
    
    def failed?
      build_status == "failed"
    end
  end
  
  # API key model for authentication
  class ApiKey < BaseModel
    include JSON::Serializable
    
    property id : Int32?
    property user_id : Int32
    property name : String
    property key : String
    property permissions : Array(String)
    property last_used : Time?
    property expires_at : Time?
    property revoked : Bool
    
    def initialize(@user_id : Int32, @name : String, @key : String)
      super()
      @permissions = ["read"] of String
      @revoked = false
    end
    
    def expired?
      if exp = expires_at
        Time.utc > exp
      else
        false
      end
    end
    
    def active?
      !revoked && !expired?
    end
  end
  
  # Search query model for analytics
  class SearchQuery < BaseModel
    include JSON::Serializable
    
    property id : Int32?
    property query : String
    property results_count : Int32
    property user_id : Int32?
    property ip_address : String?
    property user_agent : String?
    
    def initialize(@query : String, @results_count : Int32)
      super()
    end
  end
  
  # Version parsing utility
  struct Version
    include Comparable(self)
    
    getter major : Int32
    getter minor : Int32
    getter patch : Int32
    getter prerelease : String?
    getter build : String?
    
    def initialize(@major : Int32, @minor : Int32, @patch : Int32, @prerelease : String? = nil, @build : String? = nil)
    end
    
    def self.parse(version : String)
      # Basic semver parsing
      if match = version.match(/^(\d+)\.(\d+)\.(\d+)(?:-([^+]+))?(?:\+(.+))?$/)
        new(
          match[1].to_i,
          match[2].to_i,
          match[3].to_i,
          match[4]?,
          match[5]?
        )
      else
        raise "Invalid version format: #{version}"
      end
    end
    
    def <=>(other : Version)
      if (cmp = major <=> other.major) != 0
        return cmp
      end
      if (cmp = minor <=> other.minor) != 0
        return cmp
      end
      if (cmp = patch <=> other.patch) != 0
        return cmp
      end
      
      # Handle prerelease comparison
      if prerelease && other.prerelease
        prerelease <=> other.prerelease
      elsif prerelease
        -1  # prerelease < release
      elsif other.prerelease
        1   # release > prerelease
      else
        0   # both are releases
      end
    end
    
    def to_s
      result = "#{major}.#{minor}.#{patch}"
      result += "-#{prerelease}" if prerelease
      result += "+#{build}" if build
      result
    end
  end
end