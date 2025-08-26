require "http"

# HTTP Response Caching Middleware for Crystal applications
# Adds appropriate cache headers and implements conditional requests
class CacheMiddleware
  def initialize
  end

  def call(context : HTTP::Server::Context)
    request = context.request
    response = context.response

    # Set cache headers based on request path
    set_cache_headers(request, response)

    # Handle conditional requests (304 Not Modified)
    if handle_conditional_request(context)
      return
    end

    # Continue with request processing
    call_next(context)

    # Add additional headers after response processing
    finalize_cache_headers(request, response)
  end

  private def set_cache_headers(request : HTTP::Request, response : HTTP::Response)
    path = request.path

    case path
    when .starts_with?("/static/"), .starts_with?("/assets/")
      # Static assets - cache for 1 year with immutable directive
      response.headers["Cache-Control"] = "public, max-age=31536000, immutable"
      response.headers["Expires"] = (Time.utc + 1.year).to_rfc2822

    when .starts_with?("/api/search")
      # Search API results - cache for 5 minutes
      response.headers["Cache-Control"] = "public, max-age=300, stale-while-revalidate=60"
      response.headers["Vary"] = "Accept-Encoding, Accept-Language"

    when .starts_with?("/api/stats"), .starts_with?("/api/counts")
      # Statistics - cache for 30 minutes
      response.headers["Cache-Control"] = "public, max-age=1800, stale-while-revalidate=300"

    when .starts_with?("/api/shards/"), .starts_with?("/api/jobs/")
      # Individual records - cache for 15 minutes
      if request.method == "GET"
        response.headers["Cache-Control"] = "public, max-age=900, stale-while-revalidate=120"
        response.headers["ETag"] = generate_etag(path)
      end

    when /\.(css|js|png|jpg|jpeg|gif|svg|woff|woff2|ttf)$/
      # Asset files - cache for 1 week
      response.headers["Cache-Control"] = "public, max-age=604800"

    when .starts_with?("/docs/")
      # Documentation pages - cache for 1 hour
      response.headers["Cache-Control"] = "public, max-age=3600, stale-while-revalidate=300"
      response.headers["Vary"] = "Accept-Encoding"

    when .starts_with?("/")
      # HTML pages - cache for 10 minutes
      if request.method == "GET" && !path.includes?("admin")
        response.headers["Cache-Control"] = "public, max-age=600, stale-while-revalidate=60"
        response.headers["Vary"] = "Accept-Encoding, Accept-Language"
      else
        # No cache for admin pages and non-GET requests
        response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
        response.headers["Pragma"] = "no-cache"
        response.headers["Expires"] = "0"
      end
    end

    # Always add security headers
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
  end

  private def handle_conditional_request(context : HTTP::Server::Context) : Bool
    request = context.request
    response = context.response

    # Handle If-None-Match (ETag validation)
    if_none_match = request.headers["If-None-Match"]?
    if if_none_match
      current_etag = generate_etag(request.path)
      if if_none_match.includes?(current_etag) || if_none_match == "*"
        response.status = HTTP::Status::NOT_MODIFIED
        response.headers["ETag"] = current_etag
        
        # Remove content headers for 304 responses
        response.headers.delete("Content-Type")
        response.headers.delete("Content-Length")
        
        return true
      end
    end

    # Handle If-Modified-Since (Last-Modified validation)
    if_modified_since = request.headers["If-Modified-Since"]?
    if if_modified_since
      begin
        client_time = Time::Format::RFC_2822.parse(if_modified_since)
        # For simplicity, assume content is modified every hour
        # In production, this would check actual modification times
        last_modified = Time.utc.at_beginning_of_hour
        
        if client_time >= last_modified
          response.status = HTTP::Status::NOT_MODIFIED
          response.headers["Last-Modified"] = last_modified.to_rfc2822
          return true
        end
      rescue Time::Format::Error
        # Ignore invalid If-Modified-Since headers
      end
    end

    false
  end

  private def finalize_cache_headers(request : HTTP::Request, response : HTTP::Response)
    # Add Last-Modified header for GET requests
    if request.method == "GET" && !response.headers.has_key?("Last-Modified")
      # Set Last-Modified to beginning of current hour for consistent caching
      response.headers["Last-Modified"] = Time.utc.at_beginning_of_hour.to_rfc2822
    end

    # Add ETag if not present and response has content
    if !response.headers.has_key?("ETag") && request.method == "GET"
      etag = generate_etag(request.path)
      response.headers["ETag"] = etag
    end

    # Add Vary header for compressed responses
    if response.headers["Content-Encoding"]?
      current_vary = response.headers["Vary"]? || ""
      unless current_vary.includes?("Accept-Encoding")
        vary_values = current_vary.empty? ? ["Accept-Encoding"] : [current_vary, "Accept-Encoding"]
        response.headers["Vary"] = vary_values.join(", ")
      end
    end
  end

  private def generate_etag(path : String) : String
    # Generate ETag based on path and current hour
    # In production, this would include content hash or modification time
    content = "#{path}:#{Time.utc.at_beginning_of_hour.to_unix}"
    hash = Digest::SHA1.hexdigest(content)
    %("#{hash[0..15]}")
  end

  private def call_next(context : HTTP::Server::Context)
    # This would call the next middleware in the chain
    # For now, we'll assume this is handled by the framework
  end
end

# Compression middleware to reduce bandwidth usage
class CompressionMiddleware
  def initialize(@level : Int32 = 6)
  end

  def call(context : HTTP::Server::Context)
    request = context.request
    response = context.response

    # Only compress text-based responses
    should_compress = should_compress_response?(request, response)
    
    if should_compress
      accept_encoding = request.headers["Accept-Encoding"]? || ""
      
      if accept_encoding.includes?("gzip")
        response.headers["Content-Encoding"] = "gzip"
        response.headers["Vary"] = "Accept-Encoding"
        
        # In a real implementation, you would wrap the response with a Gzip::Writer
        # For now, just set the header
      elsif accept_encoding.includes?("deflate")
        response.headers["Content-Encoding"] = "deflate"  
        response.headers["Vary"] = "Accept-Encoding"
      end
    end

    call_next(context)
  end

  private def should_compress_response?(request : HTTP::Request, response : HTTP::Response) : Bool
    # Don't compress if already compressed
    return false if response.headers["Content-Encoding"]?

    # Don't compress small responses (< 1KB)
    content_length = response.headers["Content-Length"]?.try(&.to_i?)
    return false if content_length && content_length < 1024

    # Only compress text-based content types
    content_type = response.headers["Content-Type"]? || ""
    
    compressible_types = [
      "text/",
      "application/json",
      "application/javascript", 
      "application/xml",
      "application/rss+xml",
      "image/svg+xml"
    ]

    compressible_types.any? { |type| content_type.starts_with?(type) }
  end

  private def call_next(context : HTTP::Server::Context)
    # This would call the next middleware in the chain
  end
end