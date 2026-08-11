require "http/client"
require "uri"

module Discovery
  # The HTTP side of a crawl: one request at a time, with the retry and
  # rate-limit behaviour every host crawler needs.
  #
  # Three failure modes are handled differently on purpose:
  #
  #   transient (5xx, connection reset, timeout)
  #       retried with exponential backoff and jitter. These are the host having
  #       a bad second, and giving up on one would truncate a sweep.
  #
  #   rate limited (429, or 403 with a rate-limit header)
  #       waited out, using the host's own Retry-After or reset timestamp rather
  #       than a guess, then retried. If the wait is longer than the caller is
  #       willing to hold, RateLimited is raised so the sweep can stop, persist
  #       its cursor and be recorded as partial. What must never happen is
  #       dropping the rest of the pages and reporting success.
  #
  #   refused (4xx that is not a rate limit)
  #       raised immediately. Retrying a 401 or a 422 just spends quota.
  class HostClient
    class Error < Exception
    end

    # The host told us to slow down for longer than this crawl is prepared to
    # wait. Carries the wait so the caller can record why it stopped.
    class RateLimited < Exception
      getter retry_after : Time::Span

      def initialize(@retry_after : Time::Span, message : String)
        super(message)
      end
    end

    # 404 is a real answer, not a failure: it is how every host says "this
    # repository has no shard.yml at its root".
    class NotFound < Exception
    end

    USER_AGENT = "crystalshards.org shard discovery"

    getter host : String
    getter base_url : String
    getter requests_made : Int32 = 0
    getter waits : Array(Time::Span) = [] of Time::Span

    def initialize(
      @host : String,
      @base_url : String,
      @headers : HTTP::Headers,
      @max_retries : Int32 = 5,
      @max_rate_limit_wait : Time::Span = 5.minutes,
      @base_backoff : Time::Span = 1.second,
      @max_backoff : Time::Span = 30.seconds,
      @sleeper : Proc(Time::Span, Nil) = ->(duration : Time::Span) { sleep duration },
    )
      @headers["User-Agent"] = USER_AGENT unless @headers.has_key?("User-Agent")
    end

    # Returns the response body for a successful GET, raising NotFound for 404,
    # RateLimited when the host wants a longer pause than we will hold, and Error
    # when retries are exhausted or the request was refused.
    def get(path : String) : String
      attempt = 0

      loop do
        attempt += 1

        begin
          response = perform(path)

          case response.status_code
          when 200..299
            return response.body
          when 404
            raise NotFound.new("#{path} not found on #{host}")
          when 403, 429
            wait = rate_limit_wait(response)

            unless wait
              raise Error.new("#{host} refused GET #{path}: HTTP #{response.status_code} #{body_hint(response)}")
            end

            if wait > @max_rate_limit_wait
              raise RateLimited.new(wait, "#{host} rate limited GET #{path} and asked for #{format_span(wait)}, longer than this crawl will hold")
            end

            if attempt > @max_retries
              raise RateLimited.new(wait, "#{host} rate limited GET #{path} on #{attempt - 1} consecutive attempts")
            end

            pause(wait)
          when 500..599
            raise Error.new("#{host} failed GET #{path}: HTTP #{response.status_code} after #{@max_retries} retries") if attempt > @max_retries
            pause(backoff(attempt))
          else
            raise Error.new("#{host} refused GET #{path}: HTTP #{response.status_code} #{body_hint(response)}")
          end
        rescue ex : IO::Error | Socket::Error
          raise Error.new("#{host} unreachable for GET #{path} after #{@max_retries} retries: #{ex.message}") if attempt > @max_retries
          pause(backoff(attempt))
        end
      end
    end

    def get_json(path : String) : JSON::Any
      JSON.parse(get(path))
    end

    # Response headers of the last request, so a crawler can read pagination
    # hints (x-next-page, Link) without this class knowing each host's spelling.
    getter last_headers : HTTP::Headers = HTTP::Headers.new

    private def perform(path : String) : HTTP::Client::Response
      @requests_made += 1
      response = HTTP::Client.get(url_for(path), headers: @headers)
      @last_headers = response.headers
      response
    end

    private def url_for(path : String) : String
      return path if path.starts_with?("http://") || path.starts_with?("https://")

      "#{base_url.rstrip('/')}/#{path.lstrip('/')}"
    end

    # Returns how long the host wants us to wait, or nil when this response is
    # not a rate limit at all. A bare 403 is an authorization failure and must
    # not be mistaken for throttling, or a crawl with a bad token will sit in a
    # retry loop instead of reporting the token.
    private def rate_limit_wait(response : HTTP::Client::Response) : Time::Span?
      if retry_after = response.headers["Retry-After"]?
        if seconds = retry_after.strip.to_i?
          return {seconds, 0}.max.seconds
        end
      end

      # GitHub: x-ratelimit-remaining 0 with a reset timestamp. GitLab spells the
      # same pair without the x- prefix.
      remaining = response.headers["x-ratelimit-remaining"]? || response.headers["ratelimit-remaining"]?
      reset = response.headers["x-ratelimit-reset"]? || response.headers["ratelimit-reset"]?

      if remaining.try(&.strip) == "0" && reset
        if epoch = reset.strip.to_i64?
          seconds = epoch - Time.utc.to_unix
          return seconds > 0 ? seconds.seconds : 1.second
        end
      end

      # A 429 with no numbers attached is still unambiguously throttling.
      return default_rate_limit_wait if response.status_code == 429

      nil
    end

    private def default_rate_limit_wait : Time::Span
      @base_backoff * 30
    end

    # Exponential with jitter. The jitter matters because several hosts are
    # crawled by the same worker fleet and lockstep retries would arrive
    # together every time.
    private def backoff(attempt : Int32) : Time::Span
      exponential = @base_backoff * (2 ** Math.min(attempt - 1, 10))
      capped = exponential > @max_backoff ? @max_backoff : exponential
      capped * (0.75 + Random.rand * 0.5)
    end

    private def pause(duration : Time::Span)
      @waits << duration
      @sleeper.call(duration)
    end

    private def body_hint(response : HTTP::Client::Response) : String
      body = response.body.strip
      return "" if body.empty?

      body.size > 200 ? "#{body[0, 200]}..." : body
    end

    private def format_span(span : Time::Span) : String
      span.total_seconds >= 60 ? "#{(span.total_seconds / 60).round(1)}m" : "#{span.total_seconds.round}s"
    end
  end
end
