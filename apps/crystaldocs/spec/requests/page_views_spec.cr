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

# The API refuses text/html with a 406, and the collector refuses anything
# that is not a 2xx or 3xx, so asking for an API route the way a browser asks
# for a page would prove nothing about classification: the row would be absent
# because the request failed, not because the classifier said so.
private def get_json(path : String, headers : Hash(String, String) = browser_headers) : HTTP::Client::Response
  PageViewClient.new.raw_headers(headers.merge({"Accept" => "application/json"})).get(path)
end

describe "page view collection" do
  before_each do
    StatsTestTables.prepare
    StatsTestTables.truncate
  end

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

  # One request per kind the classifier produces, each through a route this
  # app actually serves. The two addressing forms matter here: a bare package
  # name sits its identity two segments deep, so package, docs_version and
  # docs_type are depths 2, 3 and 4+; the next example covers the repository
  # form, where the `_` sentinel moves the same boundary to depths 5, 6 and
  # 7+.
  it "classifies this site's routes by path shape" do
    doc = DocFactory.create &.package_name("counted-package").current_version("1.6.0")
    DocVersionFactory.create &.doc_id(doc.id).version("1.6.0")

    get_page("/")                     # home
    get_page("/docs")                 # browse: the catalogue listing
    get_page("/docs?query=kemal")     # search: the same listing with a term
    get_page("/docs/counted-package") # package: redirects to the current version

    # docs_version: a version this app holds, rendered from a planted
    # document.
    StubDocsStorage.holding.install
    get_page("/docs/counted-package/1.6.0")

    # docs_type: one level under a version. The store swaps to empty so the
    # route defers to the version page with a redirect rather than needing a
    # built artifact that names a type; the request path is what classifies.
    StubDocsStorage.empty.install
    get_page("/docs/counted-package/1.6.0/Kemal/Config")

    get_json("/api/docs") # api
    get_page("/about")    # other: a real page the classifier does not name

    kinds = PageViewQuery.new.to_a.map { |row| {row.path, row.path_kind} }
    kinds.should contain({"/", "home"})
    kinds.should contain({"/docs", "browse"})
    kinds.should contain({"/docs", "search"})
    kinds.should contain({"/docs/counted-package", "package"})
    kinds.should contain({"/docs/counted-package/1.6.0", "docs_version"})
    kinds.should contain({"/docs/counted-package/1.6.0/Kemal/Config", "docs_type"})
    kinds.should contain({"/api/docs", "api"})
    kinds.should contain({"/about", "other"})
    kinds.size.should eq(8)
  end

  # The repository form carries its package at depth five, three segments
  # deeper than the bare form, because the `_` sentinel and the three slug
  # segments come first. Off by one here files every repository front page as
  # a version and every version as a type. All three requests are the
  # standard library's repository URL, which answers with a 301 into the
  # bare "crystal" pages: recordable, and needing no rows anywhere.
  it "files the repository form at its own depths, under the _ sentinel" do
    get_page("/docs/_/github.com/crystal-lang/crystal")
    get_page("/docs/_/github.com/crystal-lang/crystal/1.21.0")
    get_page("/docs/_/github.com/crystal-lang/crystal/1.21.0/IO/Spec")

    kinds = PageViewQuery.new.to_a.map { |row| {row.path, row.path_kind} }
    kinds.should contain({"/docs/_/github.com/crystal-lang/crystal", "package"})
    kinds.should contain({"/docs/_/github.com/crystal-lang/crystal/1.21.0", "docs_version"})
    kinds.should contain({"/docs/_/github.com/crystal-lang/crystal/1.21.0/IO/Spec", "docs_type"})
    kinds.size.should eq(3)
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

  # The Content-Type is set as well as the Accept: this client's `headers`
  # call replaces the base client's defaults, one of which is the JSON
  # content type that `exec` relies on to have its body parsed. Without it
  # the action answers 400 for missing params, and a POST that never
  # succeeded would not prove the collector ignores POSTs that do.
  it "records nothing for a POST, even one that succeeds" do
    response = PageViewClient.new
      .raw_headers(browser_headers.merge({
        "Accept"       => "application/json",
        "Content-Type" => "application/json",
      }))
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
      PageViews.date_today = -> { Time.utc.date }
      get_page("/")
      PageViews.date_today = -> { (Time.utc + 1.day).date }
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
