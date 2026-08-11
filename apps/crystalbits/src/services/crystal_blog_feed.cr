require "xml"

# Reads the official Crystal blog feed.
#
# The URL is https://crystal-lang.org/feed.xml. That is the feed crystal-lang.org
# advertises as rel="alternate" on its own pages and names as <link rel="self">
# inside the document; there is no /blog/feed.xml and no /atom.xml, both 404.
# The document is Atom 1.0.
#
# We take the headline, the link, the author, the date and the summary. We do
# not take <content>, which carries the full article. Holding somebody's whole
# post so readers never have to visit their site is not curation, and a summary
# with a link is both more useful and more courteous.
class CrystalBlogFeed
  FEED_URL = "https://crystal-lang.org/feed.xml"

  DEFAULT_TIMEOUT = 10.seconds
  MAX_REDIRECTS   =   3
  SUMMARY_LIMIT   = 400

  # Raised for anything that stops us reading the feed: DNS, TLS, timeouts,
  # non-200 responses, unparseable XML. Callers treat it as "no news this run",
  # never as a reason to fail a page.
  class FetchError < Exception
  end

  record Entry,
    title : String,
    url : String,
    author : String?,
    published_at : Time?,
    summary : String

  def self.fetch(url : String = FEED_URL, timeout : Time::Span = DEFAULT_TIMEOUT) : Array(Entry)
    new(url, timeout).fetch
  end

  def initialize(@url : String = FEED_URL, @timeout : Time::Span = DEFAULT_TIMEOUT)
  end

  def fetch : Array(Entry)
    parse(get(@url))
  end

  private def get(url : String) : String
    current = url

    MAX_REDIRECTS.times do
      response = request(current)

      if response.status.redirection?
        location = response.headers["Location"]?
        raise FetchError.new("#{current} redirected without a Location header") unless location
        current = URI.parse(current).resolve(location).to_s
        next
      end

      unless response.status.success?
        raise FetchError.new("#{current} returned #{response.status_code} #{response.status.description}")
      end

      return response.body
    end

    raise FetchError.new("#{url} redirected more than #{MAX_REDIRECTS} times")
  end

  private def request(url : String) : HTTP::Client::Response
    uri = URI.parse(url)
    client = HTTP::Client.new(uri)
    client.connect_timeout = @timeout
    client.read_timeout = @timeout

    begin
      client.get(uri.request_target, headers: HTTP::Headers{
        "User-Agent" => "crystalbits.org feed reader",
        "Accept"     => "application/atom+xml, application/rss+xml, application/xml;q=0.9",
      })
    ensure
      client.close
    end
    # The network stack raises across several unrelated hierarchies, and new
    # ones appear with TLS and resolver changes. This is the boundary whose
    # whole job is that an unreachable feed must not take a page down, so it
    # catches broadly and reports precisely.


  rescue ex : FetchError
    raise ex
  rescue ex : Exception
    raise FetchError.new("could not reach #{url}: #{ex.class} #{ex.message}")
  end

  private def parse(body : String) : Array(Entry)
    document = begin
      XML.parse(body)
    rescue ex : XML::Error
      raise FetchError.new("feed at #{@url} is not parseable XML: #{ex.message}")
    end

    root = document.root
    raise FetchError.new("feed at #{@url} has no root element") unless root

    # Insist on a feed root. libxml will happily parse an HTML error page
    # served with a 200, and treating that as a feed with no entries is worse
    # than failing: "the feed is empty" and "we got an error page" would then
    # look identical, and ingestion would report success having read nothing.
    case root.name
    when "feed"
      # libxml reports local names, so Atom's default namespace needs no
      # special handling here.
      children_named(root, "entry").compact_map { |node| atom_entry(node) }
    when "rss", "rdf", "RDF"
      # The Crystal blog publishes Atom today. RSS is accepted so that a
      # switch of format degrades to working rather than to zero items.
      items = [] of XML::Node
      children_named(root, "channel").each { |channel| items.concat(children_named(channel, "item")) }
      items.concat(children_named(root, "item"))
      items.compact_map { |node| rss_entry(node) }
    else
      raise FetchError.new("#{@url} returned a <#{root.name}> document, not a feed")
    end
  end

  private def atom_entry(node : XML::Node) : Entry?
    title = text_of(node, "title")
    return nil unless title

    url = atom_link(node)
    return nil unless url

    author = children_named(node, "author").first?.try { |a| text_of(a, "name") }
    published = parse_time(text_of(node, "published") || text_of(node, "updated"))
    summary = text_of(node, "summary") || ""

    Entry.new(
      title: BitsHtml.plain_text(title),
      url: url,
      author: author,
      published_at: published,
      summary: BitsHtml.plain_text(summary, SUMMARY_LIMIT),
    )
  end

  private def rss_entry(node : XML::Node) : Entry?
    title = text_of(node, "title")
    url = text_of(node, "link")
    return nil unless title && url

    Entry.new(
      title: BitsHtml.plain_text(title),
      url: url.strip,
      author: text_of(node, "creator") || text_of(node, "author"),
      published_at: parse_time(text_of(node, "pubDate") || text_of(node, "date")),
      summary: BitsHtml.plain_text(text_of(node, "description") || "", SUMMARY_LIMIT),
    )
  end

  # Atom puts the article URL in a link element's href. Prefer the one marked
  # as the HTML alternate; fall back to the first link carrying an href.
  private def atom_link(node : XML::Node) : String?
    links = children_named(node, "link")

    alternate = links.find do |link|
      rel = link["rel"]?
      (rel.nil? || rel == "alternate") && link["href"]?
    end

    (alternate || links.find { |link| link["href"]? }).try { |link| link["href"]?.try(&.strip) }
  end

  private def children_named(node : XML::Node, name : String) : Array(XML::Node)
    node.children.select { |child| child.element? && child.name == name }
  end

  private def text_of(node : XML::Node, name : String) : String?
    children_named(node, name).first?.try(&.content).presence
  end

  # Atom dates are RFC 3339, RSS dates are RFC 2822. Try both rather than
  # assuming the format the feed happens to use today.
  private def parse_time(value : String?) : Time?
    return nil unless value

    raw = value.strip
    return nil if raw.empty?

    rfc3339(raw) || rfc2822(raw)
  end

  private def rfc3339(raw : String) : Time?
    Time.parse_rfc3339(raw)
  rescue
    nil
  end

  private def rfc2822(raw : String) : Time?
    Time.parse_rfc2822(raw)
  rescue
    nil
  end
end
