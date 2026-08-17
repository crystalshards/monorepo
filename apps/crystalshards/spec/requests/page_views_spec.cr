require "../spec_helper"

# Drives requests with the verbatim headers collection reads: User-Agent,
# Referer, and the two the load balancer sets. Lucky's `headers` helper
# rewrites dashes to underscores, which would silently send none of them.
private class PageViewClient < Lucky::BaseHTTPClient
  app AppServer.new

  def initialize
    super
    headers("Accept": "text/html")
  end

  def raw_headers(values : Hash(String, String)) : self
    client.before_request do |request|
      values.each { |name, value| request.headers[name] = value }
    end
    self
  end
end

# The collector's bot rule only passes the mainstream-browser shape, which
# the test client's default agent ("Crystal") deliberately is not.
private def browser_ua : String
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
end

private def browser_headers(ip : String = "203.0.113.7", user_agent : String = browser_ua) : Hash(String, String)
  {"User-Agent" => user_agent, "X-Client-IP" => ip}
end

private def get_page(path : String, headers : Hash(String, String) = browser_headers) : HTTP::Client::Response
  PageViewClient.new.raw_headers(headers).get(path)
end

describe "page view collection" do
  it "records exactly one row for a normal request, with the path kind" do
    response = get_page("/")

    response.status_code.should eq(200)

    rows = PageViewQuery.new.to_a
    rows.size.should eq(1)
    rows.first.path.should eq("/")
    rows.first.path_kind.should eq("home")
    rows.first.visitor_hash.size.should eq(64)
    rows.first.occurred_at.should be_close(Time.utc, 5.seconds)
  end

  it "classifies browse, search, package and api by path shape" do
    shard = ShardFactory.create &.name("counted-shard")

    get_page("/shards")
    get_page("/shards?query=kemal")
    get_page("/shards/#{shard.host}/#{shard.owner}/#{shard.repo}")
    get_page("/api/shards")

    kinds = PageViewQuery.new.to_a.map { |row| {row.path, row.path_kind} }
    kinds.should contain({"/shards", "browse"})
    kinds.should contain({"/shards", "search"})
    kinds.should contain({"/shards/#{shard.host}/#{shard.owner}/#{shard.repo}", "package"})
    kinds.should contain({"/api/shards", "api"})
    kinds.size.should eq(4)
  end

  it "records nothing for a known bot, whatever page it asks for" do
    get_page("/", headers: browser_headers(user_agent: "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"))
    get_page("/", headers: browser_headers(user_agent: "Googlebot/2.1 (+http://www.google.com/bot.html)"))
    get_page("/", headers: browser_headers(user_agent: "curl/8.7.1"))
    get_page("/", headers: browser_headers(user_agent: ""))

    PageViewQuery.new.select_count.should eq(0)
  end

  describe "the bot matcher" do
    it "passes the mainstream browser shapes" do
      PageViews.bot?(browser_ua).should be_false
      PageViews.bot?("Mozilla/5.0 (X11; Linux x86_64; rv:127.0) Gecko/20100101 Firefox/127.0").should be_false
    end

    it "refuses honest crawlers, bare-token bots, and non-browser clients" do
      PageViews.bot?("Mozilla/5.0 (compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm)").should be_true
      PageViews.bot?("DuckDuckBot/1.1; (+http://duckduckgo.com/duckduckbot.html)").should be_true
      PageViews.bot?("python-requests/2.32.3").should be_true
      PageViews.bot?(nil).should be_true
    end

    it "counts headless Chrome as the reader it is" do
      PageViews.bot?("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) HeadlessChrome/126.0.0.0 Safari/537.36").should be_false
    end
  end

  it "records nothing for an asset, even one that answers 200" do
    response = get_page("/favicon.ico")

    response.status_code.should eq(200)
    PageViewQuery.new.select_count.should eq(0)
  end

  it "records nothing for a page that is not there" do
    response = get_page("/definitely-not-a-page")

    response.status_code.should eq(404)
    PageViewQuery.new.select_count.should eq(0)
  end

  it "records nothing for a POST, even one that succeeds" do
    response = PageViewClient.new.raw_headers(browser_headers)
      .exec(Api::SignUps::Create, user: {
        email:                 "a-reader@example.com",
        password:              "correct horse battery staple",
        password_confirmation: "correct horse battery staple",
      })

    response.status_code.should eq(200)
    PageViewQuery.new.select_count.should eq(0)
  end

  it "counts a HEAD request as the read it is" do
    response = PageViewClient.new.raw_headers(browser_headers).head("/")

    response.status_code.should eq(200)
    PageViewQuery.new.select_count.should eq(1)
  end

  it "gives one visitor one hash across a day, and a row per view" do
    2.times { get_page("/") }

    rows = PageViewQuery.new.to_a
    rows.size.should eq(2)
    rows.map(&.visitor_hash).uniq.size.should eq(1)
  end

  it "turns the hash over when the salt's date does" do
    original = PageViews.date_today
    begin
      PageViews.date_today = ->{ Time.utc.date }
      get_page("/")
      PageViews.date_today = ->{ (Time.utc + 1.day).date }
      get_page("/")

      rows = PageViewQuery.new.to_a
      rows.size.should eq(2)
      rows[0].visitor_hash.should_not eq(rows[1].visitor_hash)
    ensure
      PageViews.date_today = original
    end
  end

  it "stores only the host of a referrer, and none when there is none" do
    get_page("/", headers: browser_headers.merge({"Referer" => "HTTPS://WWW.Example.com/some/reading?query=private"}))
    get_page("/")

    rows = PageViewQuery.new.occurred_at.asc_order.to_a
    rows.size.should eq(2)
    rows[0].referrer_host.should eq("www.example.com")
    rows[1].referrer_host.should be_nil
  end

  it "stores the country the load balancer sent, and none when it sent none" do
    get_page("/", headers: browser_headers.merge({"X-Client-Geo-Location" => "SE"}))
    get_page("/")

    rows = PageViewQuery.new.occurred_at.asc_order.to_a
    rows.size.should eq(2)
    rows[0].country.should eq("SE")
    rows[1].country.should be_nil
  end

  it "never writes the address, in the row or in any log line" do
    ip = "198.51.100.23"
    original_inserter = PageViews.inserter
    mem = Log::MemoryBackend.new
    Log.builder.bind("*", Log::Severity::Trace, mem)
    begin
      # The row that lands carries a digest, and the write forced to fail
      # below proves the address is not in anything the request logged
      # either, including the collector's own error line.
      get_page("/", headers: browser_headers(ip: ip))

      PageViews.inserter = ->(_row : PageViews::Row) { raise "database is on fire" }
      get_page("/", headers: browser_headers(ip: ip))
    ensure
      PageViews.inserter = original_inserter
      Log.builder.unbind("*", Log::Severity::Trace, mem)
    end

    rows = PageViewQuery.new.to_a
    rows.size.should eq(1)
    rows.first.visitor_hash.should_not contain(ip)

    # Positive control: the failed write did log its refusal, so the capture
    # above cannot be passing on an empty log.
    mem.entries.map(&.message).join("\n").should contain("was not recorded")
    mem.entries.each do |entry|
      entry.message.should_not contain(ip)
      entry.exception.to_s.should_not contain(ip)
    end
  end

  it "swallows a failed insert and still answers the page" do
    original_inserter = PageViews.inserter
    begin
      PageViews.inserter = ->(_row : PageViews::Row) { raise "database is on fire" }

      response = get_page("/")

      response.status_code.should eq(200)
      PageViewQuery.new.select_count.should eq(0)
    ensure
      PageViews.inserter = original_inserter
    end
  end
end
