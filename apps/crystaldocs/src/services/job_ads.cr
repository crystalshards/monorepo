require "http/client"
require "json"
require "uri"
require "../../config/job_ads"

module CrystalDocs
  # Promotable jobs from CrystalGigs, for the ad strip.
  #
  # Three properties drive every decision in here, in this order.
  #
  # 1. A page render never waits on CrystalGigs for long. The timeouts below
  #    are the whole budget, and only one request per TTL pays them: a cache
  #    hit serves from memory without touching the network, and while a fetch
  #    is in flight every other request renders nothing rather than queueing
  #    behind it.
  # 2. A failure means no ad. Not a stale ad, not an empty box, not a spinner.
  #    A failed fetch clears the cache, so the strip disappears rather than
  #    advertising jobs we can no longer confirm are open.
  # 3. A dead CrystalGigs costs one request per backoff window, not one per
  #    page view. Otherwise the site that just lost its ad source would also
  #    spend a socket and a timeout on every single render.
  module JobAds
    # One advertised job. Fields outside this list are ignored, which is what
    # stops a change to the CrystalGigs API from silently widening what three
    # other sites put on every page.
    struct Ad
      include JSON::Serializable

      getter title : String
      getter company : String
      getter location : String?
      getter url : String
      getter? remote : Bool = false
      getter? featured : Bool = false

      # The feed is first-party, but it is still a network response being
      # written into our markup, so the href is scheme-checked rather than
      # trusted. `javascript:` is a link too.
      def safe_url? : Bool
        uri = URI.parse(url)
        uri.absolute? && {"http", "https"}.includes?(uri.scheme)
      rescue URI::Error
        false
      end
    end

    NONE = [] of Ad

    # Long enough that this site costs CrystalGigs one request every five
    # minutes. Short enough that a job posted this morning is advertised this
    # morning.
    CACHE_TTL = 5.minutes

    # After a failure, stand down for a while. A busy site would otherwise
    # open a socket and burn the timeout on every render for as long as
    # CrystalGigs stays down.
    FAILURE_BACKOFF = 30.seconds

    # The entire budget a page render may spend on an ad. Deliberately under a
    # second in total: an ad is the least important thing on the page, so it
    # gets the smallest slice of the reader's patience.
    CONNECT_TIMEOUT = 400.milliseconds
    READ_TIMEOUT    = 600.milliseconds
    WRITE_TIMEOUT   = 400.milliseconds

    # Timeouts bound how long a read may stall, not how much arrives, so the
    # body is capped too. A promotable feed is a handful of rows; anything
    # larger is a misconfigured endpoint or not our feed at all, and a page
    # render is the wrong place to find out which.
    MAX_BODY_BYTES = 64 * 1024

    # Fetches the raw feed body, or nil for any failure at all. Replaced in
    # specs, mirroring the test seam the other services use.
    alias Transport = Proc(String?)

    @@transport : Transport? = nil
    @@mutex = Mutex.new
    @@ads : Array(Ad) = NONE
    @@cached_at : Time? = nil
    @@next_attempt_at : Time = Time.unix(0)
    @@fetching = false

    # nil restores the real HTTP call.
    def self.transport=(transport : Transport?)
      @@transport = transport
    end

    # What the ad strip should render right now. Never raises.
    def self.current(limit : Int32) : Array(Ad)
      return NONE unless JobAdsConfig.enabled?
      return NONE if limit < 1

      now = Time.utc

      # One critical section decides everything: serve, stand down, or claim
      # the fetch. Reading the cache and taking the in-flight claim have to be
      # a single atomic step, or two requests arriving together both conclude
      # they are the fetcher.
      decision = @@mutex.synchronize do
        cached_at = @@cached_at

        if cached_at && now - cached_at <= CACHE_TTL
          next {:serve, @@ads}
        end

        # Backing off from a recent failure, or another fiber already has the
        # socket. Either way this request renders nothing and does not wait:
        # an ad is not worth making a reader hold on for.
        next {:stand_down, NONE} if now < @@next_attempt_at || @@fetching

        @@fetching = true
        {:claimed, NONE}
      end

      state, cached = decision
      return cached.first(limit) if state == :serve
      return NONE if state == :stand_down

      refresh(now).first(limit)
    end

    # Synchronous fetch and store. Returns what the strip should render.
    private def self.refresh(now : Time) : Array(Ad)
      # Outside the mutex on purpose. Holding the lock across a network call
      # would serialise every page render in the process behind one socket.
      store(now, fetch)
    ensure
      # `store` already clears the claim on every path it can take. This is
      # here so no future edit above can leave the flag stuck true, which
      # would silently disable the strip for the life of the process and look
      # exactly like CrystalGigs having no jobs.
      @@mutex.synchronize { @@fetching = false }
    end

    private def self.store(now : Time, ads : Array(Ad)?) : Array(Ad)
      @@mutex.synchronize do
        @@fetching = false

        if ads
          # An empty list is a real answer: the board has nothing to
          # advertise. It is cached like any other success, so an idle job
          # board does not turn into a retry loop.
          @@ads = ads
          @@cached_at = now
          @@next_attempt_at = now
          ads
        else
          # A failure invalidates what we had. Showing yesterday's jobs
          # because today's fetch failed is the dishonest option: those roles
          # may be filled and we can no longer check.
          @@ads = NONE
          @@cached_at = nil
          @@next_attempt_at = now + FAILURE_BACKOFF
          NONE
        end
      end
    end

    # nil for every failure: unreachable, slow, non-200, oversized,
    # unparseable. The caller does not care which, only that there is no ad.
    #
    # The bare rescue is deliberate and belongs exactly here. This runs inside
    # a page render on a site that has nothing to do with CrystalGigs, so
    # there is no failure of an ad that may be allowed to fail a page: not a
    # TLS error, not a redirect loop, not a bug in our own parsing. The log
    # line is how such a bug gets found, rather than a 500 on every page.
    private def self.fetch : Array(Ad)?
      body = transport.call
      return nil unless body

      parse(body)
    rescue ex
      Log.for("job_ads").warn { "job ads fetch failed: #{ex.class}: #{ex.message}" }
      nil
    end

    private def self.transport : Transport
      @@transport || -> { default_transport }
    end

    # Separated from the transport so the parsing rules are testable without a
    # socket, and so a malformed payload can never escape as an exception into
    # a page render.
    def self.parse(body : String) : Array(Ad)?
      Feed.from_json(body).jobs.select(&.safe_url?)
    rescue ex : JSON::Error
      Log.for("job_ads").warn { "unparseable job ads feed: #{ex.message}" }
      nil
    end

    private struct Feed
      include JSON::Serializable

      getter jobs : Array(Ad) = [] of Ad
    end

    # Everything the network can do to us, collapsed into "no ad". An ad strip
    # is never a reason for a page to fail.
    private def self.default_transport : String?
      endpoint = JobAdsConfig.endpoint
      return nil unless endpoint

      client = HTTP::Client.new(endpoint)
      client.connect_timeout = CONNECT_TIMEOUT
      client.read_timeout = READ_TIMEOUT
      client.write_timeout = WRITE_TIMEOUT

      begin
        client.get(endpoint.request_target) do |response|
          return nil unless response.status.success?

          # One byte over the cap is enough to know it is over the cap, and
          # stops here rather than after reading an arbitrary amount.
          buffer = IO::Memory.new
          IO.copy(response.body_io, buffer, MAX_BODY_BYTES + 1)
          return nil if buffer.bytesize > MAX_BODY_BYTES

          buffer.to_s
        end
      ensure
        client.close
      end
    rescue ex : IO::Error | Socket::Error | URI::Error
      Log.for("job_ads").warn { "job ads feed unreachable: #{ex.message}" }
      nil
    end

    # Test seam. Drops the cache and the backoff so an example starts cold.
    def self.reset!
      @@mutex.synchronize do
        @@ads = NONE
        @@cached_at = nil
        @@next_attempt_at = Time.unix(0)
        @@fetching = false
      end
    end
  end
end
