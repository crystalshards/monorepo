require "digest/sha256"
require "uri"

# Records one row per real page view, server side, with no cookie and no
# client code. These sites promise to render with scripting off, so the
# collector lives in the handler stack rather than in a beacon a reader can
# block; and with no cookie set and no address stored there is nothing to
# ask consent for and nothing to leak. Every fact the row carries was
# already in the request.
#
# This file is intentionally identical in every app, the same way
# config/site_links.cr is: the apps build as independent images with
# apps/<app> as the docker context, so a shared module has no home to live
# in, and keeping the four copies byte-identical makes drift a one-line
# `cmp` instead of a merge. The one thing that genuinely differs per app,
# which paths count as which kind of page, lives in page_view_kinds.cr.
module PageViews
  # What one recorded view is made of. The values are pulled out of the
  # request before the write is handed to another fiber, so nothing
  # asynchronous ever touches the context: the server reuses it for the next
  # request on the connection.
  record Row,
    path : String,
    path_kind : String,
    referrer_host : String?,
    country : String?,
    visitor_hash : String,
    occurred_at : Time

  INSERT_SQL = <<-SQL
    INSERT INTO page_views (path, path_kind, referrer_host, country, visitor_hash, occurred_at)
    VALUES ($1, $2, $3, $4, $5, $6)
    SQL

  # Off the request's fiber everywhere but in the suite. A write that stood
  # between the action and the reader would make analytics the slowest
  # feature the site has, so the handler spawns it and the response closes
  # without waiting on it. The suite runs it inline instead: a spec cannot
  # assert on a row that may not have landed yet.
  class_property async_writes : Bool = !LuckyEnv.test?

  # Test seam, the same shape as ShardIndexRequests.indexer: production runs
  # the real insert, a spec installs a double to force the failure path
  # without breaking the database, and restores it in an ensure.
  class_property inserter : Proc(Row, Nil) = ->(row : Row) { insert_row(row) }

  # Test seam: the date the daily salt rotates on. A spec moves it forward
  # to prove a visitor's hash turns over; production reads the real clock.
  # Crystal has no calendar-date type; Time#date's {year, month, day} tuple
  # is exactly comparable for "is it still today".
  class_property date_today : Proc(Tuple(Int32, Int32, Int32)) = -> { Time.utc.date }

  # Called once per request by PageViewHandler, after the rest of the stack
  # has answered. Everything refused here is not a page view: a bot, an
  # asset, the health endpoint, a write, or a response that was not a page.
  def self.record(context : HTTP::Server::Context) : Nil
    request = context.request

    return unless recordable_status?(context.response.status_code)
    return unless recordable_method?(request.method)
    return if health_check?(request.path)
    return if asset?(request.path)
    return if bot?(request.headers["User-Agent"]?)

    write Row.new(
      path: request.path,
      path_kind: path_kind(request),
      referrer_host: referrer_host(request),
      country: country(request),
      visitor_hash: visitor_hash(client_ip(request), request.headers["User-Agent"]? || ""),
      occurred_at: Time.utc
    )
  end

  # 2xx and 3xx only. A 404 is not a view of anything and a 500 is a page
  # nobody chose to read. A redirect still counts: the reader asked for that
  # URL and the route answered it, which is what a view is.
  private def self.recordable_status?(status : Int32) : Bool
    200 <= status < 400
  end

  # A view is a read. A POST is the reader doing something rather than
  # looking at something, and the page it lands on is counted when that page
  # renders. HEAD is a read: LuckyRouter registers a HEAD twin for every GET
  # route, so a HEAD that got a 2xx here is a route that answered.
  private def self.recordable_method?(method : String) : Bool
    method == "GET" || method == "HEAD"
  end

  # The load balancer's uptime probe is not a reader.
  private def self.health_check?(path : String) : Bool
    path == "/api/health"
  end

  # Everything the static handler can answer: the three directories under
  # public/, and the root files a browser asks for on its own. The page
  # routes in these apps never live under either, so the check is a shape,
  # not a list of filenames. A new top-level directory in public/ belongs in
  # ASSET_PREFIXES; until it is added its files are counted as `other`,
  # which is the failure that is visible rather than the one that is not.
  ASSET_PREFIXES = %w[/css/ /js/ /images/]
  ASSET_FILES    = %w[/favicon.ico /apple-touch-icon.png /icon.svg /icon-192.png /icon-512.png /manifest.json /mix-manifest.json /robots.txt /sitemap.xml]

  private def self.asset?(path : String) : Bool
    ASSET_FILES.includes?(path) || ASSET_PREFIXES.any? { |prefix| path.starts_with?(prefix) }
  end

  # A view counts when the agent presents as a graphical browser, and a
  # living browser presents two shapes:
  #
  #   * it starts with "Mozilla/5.0 (" -- Chrome, Firefox, Safari, Edge and
  #     Opera all do, and nothing else of consequence does;
  #   * it does not carry the "(compatible;" token, which is how an honest
  #     crawler introduces itself inside a Mozilla preamble (Googlebot,
  #     Bingbot, AhrefsBot, SemrushBot all wear it), and which no living
  #     browser emits.
  #
  # So this refuses by shape rather than by name: every curl/wget/SDK client
  # (no Mozilla preamble), every bare-token bot (Googlebot/2.1, Twitterbot,
  # DuckDuckBot, UptimeRobot -- also no preamble), and every crawler that
  # declares itself with (compatible;. It never needs a vendor name added to
  # it, which is what a denylist of bot names always needs.
  #
  # What it will NOT catch, deliberately: a bot that sends an exact copy of
  # a real browser's user agent is lying, and a liar is out of scope, named
  # as such here -- no server-side rule can see through a perfect copy.
  # Headless Chrome is the honest version of that shape and is counted as a
  # reader, because it is one. The matcher also refuses everything that is
  # not a mainstream browser, which costs the occasional Lynx reader and the
  # long-dead IE<=10; both are named here so the undercount is a decision
  # and not a surprise.
  BROWSER_PREAMBLE = "Mozilla/5.0 ("
  CRAWLER_TOKEN    = "(compatible;"

  def self.bot?(user_agent : String?) : Bool
    return true if user_agent.nil? || user_agent.blank?
    return true unless user_agent.starts_with?(BROWSER_PREAMBLE)
    return true if user_agent.includes?(CRAWLER_TOKEN)
    false
  end

  # The address the load balancer observed, delivered as its own header.
  #
  # The edge's backend services set X-Client-IP to {client_ip_address}: the
  # load balancer expands that variable from the TCP peer it terminated and
  # overwrites any client-supplied header of the same name, so the value
  # cannot be spoofed from the internet. The four services take
  # INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER only, so every request in
  # production carries it. This is deliberately NOT X-Forwarded-For: entries
  # there before the last two are client-supplied, the last is the balancer
  # itself, and Lucky::RemoteIpHandler picks exactly that last one, which is
  # why the collector reads its own header rather than remote_address.
  #
  # The socket address is the fallback only where there is no load balancer
  # at all (development, the test suite), where the peer is honest by
  # construction. With neither, the hash salts against an empty string; in
  # production that shape cannot occur.
  IP_HEADER = "X-Client-IP"

  private def self.client_ip(request : HTTP::Request) : String
    request.headers[IP_HEADER]?.presence ||
      request.remote_address.try(&.to_s) ||
      ""
  end

  # The country the load balancer resolved for the client, or nil.
  #
  # Same delivery and same trust as X-Client-IP: the edge sets
  # X-Client-Geo-Location to {client_region}, a CLDR region code such as US
  # or FR, overwriting anything the client sent. When the balancer cannot
  # resolve one it expands the variable to empty, which is recorded as NULL
  # rather than guessed from the address -- a VPN reader counts as unknown,
  # never as a wrong country.
  GEO_HEADER = "X-Client-Geo-Location"

  private def self.country(request : HTTP::Request) : String?
    request.headers[GEO_HEADER]?.presence
  end

  # The host of the Referer, lowercased, or nil. The full URL is never
  # stored: a referring path can carry what the reader was reading, and the
  # rollup only ever groups by host. Nil means no referrer or an
  # unparseable one; the daily rollup folds it into its 'direct' bucket.
  private def self.referrer_host(request : HTTP::Request) : String?
    referer = request.headers["Referer"]?.presence
    return nil unless referer

    URI.parse(referer).host.presence.try(&.downcase)
  rescue URI::Error
    nil
  end

  # SHA256(daily salt + client IP + user agent): a count of people that is
  # not a record of them. The raw address is never written, here or in any
  # log line, and the hash cannot be walked back to one reader because the
  # salt dies with the day and with the process. The newlines separate the
  # parts so no split of address and agent can collide.
  def self.visitor_hash(client_ip : String, user_agent : String) : String
    Digest::SHA256.hexdigest("#{daily_salt}\n#{client_ip}\n#{user_agent}")
  end

  @@salt : String?
  @@salt_date : Tuple(Int32, Int32, Int32)?
  @@salt_lock = Mutex.new

  # The salt lives only in this process's memory and turns over when the UTC
  # date does. Nothing persists it: a daily salt is what stops yesterday's
  # hash identifying today's reader, and a written-down salt would outlive
  # the property it exists for. A restart rotates it early, which is
  # acceptable and one-directional: it can only ever split one visitor into
  # two, never merge two into one.
  private def self.daily_salt : String
    today = date_today.call

    @@salt_lock.synchronize do
      if @@salt.nil? || @@salt_date != today
        @@salt = Random::Secure.hex(32)
        @@salt_date = today
      end
      @@salt.not_nil!
    end
  end

  private def self.write(row : Row) : Nil
    if async_writes
      spawn { run_insert(row) }
    else
      run_insert(row)
    end
  end

  private def self.run_insert(row : Row) : Nil
    inserter.call(row)
  rescue ex : Exception
    # A page view that cannot be written is a lost row, never a failed page:
    # the reader already has their response, and nothing they did caused
    # this. The path is the only request fact worth logging with it; the
    # address is absent here the same way it is absent everywhere else.
    Log.for("page_views").error(exception: ex) { "A page view for #{row.path} was not recorded" }
  end

  private def self.insert_row(row : Row) : Nil
    AppDatabase.exec(
      INSERT_SQL,
      row.path,
      row.path_kind,
      row.referrer_host,
      row.country,
      row.visitor_hash,
      row.occurred_at
    )
  end
end
