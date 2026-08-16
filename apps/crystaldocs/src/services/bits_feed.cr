require "http/client"
require "json"
require "uri"
require "../../config/site_links"

module CrystalDocs
  # Recent articles from CrystalBits, for the sister-site strip on the home
  # page.
  #
  # Three properties drive every decision in here, in this order.
  #
  # 1. A page render never waits on CrystalBits for long. The timeouts below
  #    are the whole budget, and only one request per TTL pays them: a cache
  #    hit serves from memory without touching the network, and while a fetch
  #    is in flight every other request renders nothing rather than queueing
  #    behind it.
  # 2. A failure means no strip. Not stale articles, not an empty box, not a
  #    spinner. A failed fetch clears the cache, so the strip disappears
  #    rather than advertising articles we can no longer confirm are
  #    published.
  # 3. A dead CrystalBits costs one request per backoff window, not one per
  #    page view. Otherwise the site that just lost its article source would
  #    also spend a socket and a timeout on every single render.
  module BitsFeed
    # One recent article. Fields outside this list are ignored, which is what
    # stops a change to the CrystalBits API from silently widening what three
    # other sites put on their home pages.
    struct Article
      include JSON::Serializable

      getter title : String
      getter slug : String
      getter excerpt : String?

      # The feed carries no URL; the strip composes one from the configured
      # origin and this slug, so the slug is the part of the link a network
      # response controls. The feed is first-party, but it is still a network
      # response being written into our markup, so anything that is not a
      # plain slug, a full URL, a path with dots or slashes, a javascript:
      # payload wearing a slug's clothes, is refused rather than rendered.
      def safe_slug? : Bool
        SLUG_PATTERN.matches?(slug)
      end
    end

    NONE = [] of Article

    # The strip shows three at most, and asks the feed for exactly that many.
    MAX_ARTICLES = 3

    # What a slug looks like once CrystalBits has normalized it: lowercase
    # words joined by single hyphens. A slug that does not match is not a
    # slug, and the article carrying it does not get a link.
    SLUG_PATTERN = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/

    # Long enough that this site costs CrystalBits one request every five
    # minutes. Short enough that an article posted this morning is on the
    # home page this morning.
    CACHE_TTL = 5.minutes

    # After a failure, stand down for a while. A busy site would otherwise
    # open a socket and burn the timeout on every render for as long as
    # CrystalBits stays down.
    FAILURE_BACKOFF = 30.seconds

    # The entire budget a page render may spend on the strip. Deliberately
    # under a second in total: the strip is the least important thing on the
    # page, so it gets the smallest slice of the reader's patience.
    CONNECT_TIMEOUT = 400.milliseconds
    READ_TIMEOUT    = 600.milliseconds
    WRITE_TIMEOUT   = 400.milliseconds

    # Timeouts bound how long a read may stall, not how much arrives, so the
    # body is capped too. Three recent articles are a handful of rows;
    # anything larger is a misconfigured endpoint or not our feed at all, and
    # a page render is the wrong place to find out which.
    MAX_BODY_BYTES = 64 * 1024

    # Fetches the raw feed body, or nil for any failure at all. Replaced in
    # specs, mirroring the test seam the other services use.
    alias Transport = Proc(String?)

    @@transport : Transport? = nil
    @@origin : String? = nil
    @@mutex = Mutex.new
    @@articles : Array(Article) = NONE
    @@cached_at : Time? = nil
    @@next_attempt_at : Time = Time.unix(0)
    @@fetching = false

    # nil restores the real HTTP call.
    def self.transport=(transport : Transport?)
      @@transport = transport
    end

    # nil restores SiteLinks. Writable so a spec can point the strip at a
    # stub origin without reaching into the process environment; the value
    # production renders with still comes from SiteLinks.
    def self.origin=(origin : String?)
      @@origin = origin
    end

    # Where CrystalBits answers, from configuration, or nil when no origin is
    # set. Outside production the four site origins are allowed to be absent,
    # and a strip without a target renders nothing rather than guessing one.
    def self.origin : String?
      @@origin || SiteLinks.origin(:crystalbits)
    rescue SiteLinks::MissingOrigin | SiteLinks::MalformedOrigin
      nil
    end

    # The URL a card links to. Composed here, from the configured origin and
    # a slug that has already survived safe_slug?, so no other site ever
    # writes a CrystalBits URL out of a bare hostname.
    def self.article_url(origin : String, article : Article) : String
      "#{origin}/posts/#{article.slug}"
    end

    # What the strip should render right now. Never raises.
    def self.current(limit : Int32 = MAX_ARTICLES) : Array(Article)
      origin = self.origin
      return NONE unless origin
      return NONE if limit < 1

      now = Time.utc

      # One critical section decides everything: serve, stand down, or claim
      # the fetch. Reading the cache and taking the in-flight claim have to
      # be a single atomic step, or two requests arriving together both
      # conclude they are the fetcher.
      decision = @@mutex.synchronize do
        cached_at = @@cached_at

        if cached_at && now - cached_at <= CACHE_TTL
          next {:serve, @@articles}
        end

        # Backing off from a recent failure, or another fiber already has the
        # socket. Either way this request renders nothing and does not wait:
        # the strip is not worth making a reader hold on for.
        next {:stand_down, NONE} if now < @@next_attempt_at || @@fetching

        @@fetching = true
        {:claimed, NONE}
      end

      state, cached = decision
      return cached.first(limit) if state == :serve
      return NONE if state == :stand_down

      refresh(now, origin, limit)
    end

    # Synchronous fetch and store. Returns what the strip should render.
    private def self.refresh(now : Time, origin : String, limit : Int32) : Array(Article)
      # Outside the mutex on purpose. Holding the lock across a network call
      # would serialise every page render in the process behind one socket.
      articles = fetch(origin)
      store(now, articles).first(limit)
    ensure
      # `store` already clears the claim on every path it can take. This is
      # here so no future edit above can leave the flag stuck true, which
      # would silently disable the strip for the life of the process and look
      # exactly like CrystalBits having published nothing.
      @@mutex.synchronize { @@fetching = false }
    end

    private def self.store(now : Time, articles : Array(Article)?) : Array(Article)
      @@mutex.synchronize do
        @@fetching = false

        if articles
          # An empty list is a real answer: CrystalBits has nothing recent to
          # show. It is cached like any other success, so a quiet week does
          # not turn into a retry loop.
          @@articles = articles
          @@cached_at = now
          @@next_attempt_at = now
          articles
        else
          # A failure invalidates what we had. Showing yesterday's articles
          # because today's fetch failed is the dishonest option: they may
          # have been corrected or withdrawn and we can no longer check.
          @@articles = NONE
          @@cached_at = nil
          @@next_attempt_at = now + FAILURE_BACKOFF
          NONE
        end
      end
    end

    # nil for every failure: unreachable, slow, non-200, oversized,
    # unparseable. The caller does not care which, only that there is no
    # strip.
    #
    # The bare rescue is deliberate and belongs exactly here. This runs
    # inside a page render on a site that has nothing to do with CrystalBits,
    # so there is no failure of the strip that may be allowed to fail a page:
    # not a TLS error, not a redirect loop, not a bug in our own parsing. The
    # log line is how such a bug gets found, rather than a 500 on every page.
    private def self.fetch(origin : String) : Array(Article)?
      body = transport.call
      return nil unless body

      parse(body, origin)
    rescue ex
      Log.for("bits_feed").warn { "bits feed fetch failed: #{ex.class}: #{ex.message}" }
      nil
    end

    private def self.transport : Transport
      @@transport || -> { default_transport }
    end

    # Separated from the transport so the parsing rules are testable without
    # a socket, and so a malformed payload can never escape as an exception
    # into a page render.
    def self.parse(body : String, origin : String) : Array(Article)?
      Feed.from_json(body).posts.select(&.safe_slug?).first(MAX_ARTICLES)
    rescue ex : JSON::Error
      Log.for("bits_feed").warn { "unparseable bits feed: #{ex.message}" }
      nil
    end

    private struct Feed
      include JSON::Serializable

      getter posts : Array(Article) = [] of Article
    end

    # Everything the network can do to us, collapsed into "no strip". A link
    # list is never a reason for a page to fail.
    private def self.default_transport : String?
      origin = self.origin
      return nil unless origin

      endpoint = URI.parse("#{origin}/api/posts?per_page=#{MAX_ARTICLES}")
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
      Log.for("bits_feed").warn { "bits feed unreachable: #{ex.message}" }
      nil
    end

    # Test seam. Drops the cache and the backoff so an example starts cold.
    def self.reset!
      @@mutex.synchronize do
        @@articles = NONE
        @@cached_at = nil
        @@next_attempt_at = Time.unix(0)
        @@fetching = false
      end
    end
  end
end
