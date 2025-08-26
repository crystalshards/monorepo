require "json"

module CrystalShards
  # Search options for advanced filtering and sorting
  struct SearchOptions
    include JSON::Serializable

    property license : String?
    property crystal_version : String?
    property tag : String?
    property min_stars : Int32?
    property featured_only : Bool = false
    property updated_within_days : Int32?
    property sort_by : String = "relevance" # relevance, stars, downloads, recent, name

    def initialize(
      @license = nil,
      @crystal_version = nil,
      @tag = nil,
      @min_stars = nil,
      @featured_only = false,
      @updated_within_days = nil,
      @sort_by = "relevance"
    )
    end

    # Create cache key from options for proper cache differentiation
    def to_cache_key : String
      parts = [] of String
      parts << "license:#{license}" if license
      parts << "version:#{crystal_version}" if crystal_version
      parts << "tag:#{tag}" if tag
      parts << "stars:#{min_stars}" if min_stars
      parts << "featured" if featured_only
      parts << "days:#{updated_within_days}" if updated_within_days
      parts << "sort:#{sort_by}" if sort_by != "relevance"
      
      parts.empty? ? "default" : parts.join("|")
    end

    # Parse from query parameters
    def self.from_params(params : Hash(String, String)) : SearchOptions
      SearchOptions.new(
        license: params["license"]?.presence,
        crystal_version: params["crystal_version"]?.presence,
        tag: params["tag"]?.presence,
        min_stars: params["min_stars"]?.try(&.to_i?),
        featured_only: params["featured_only"]? == "true",
        updated_within_days: params["updated_within_days"]?.try(&.to_i?),
        sort_by: params["sort_by"]?.presence || "relevance"
      )
    end

    # Validate sort options
    def valid_sort_by? : Bool
      ["relevance", "stars", "downloads", "recent", "name"].includes?(sort_by)
    end
  end
end