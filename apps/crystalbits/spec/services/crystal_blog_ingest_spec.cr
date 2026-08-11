require "../spec_helper"

# A port nothing is listening on. Refused instantly, so the spec proves the
# error handling without sitting through a network timeout.
private UNREACHABLE = "http://127.0.0.1:1/feed.xml"

# A trimmed copy of the shape crystal-lang.org actually serves: Atom 1.0, an
# author name, an alternate link, an RFC 3339 published date, an HTML summary,
# and a full <content> body we must not store.
private ATOM_FEED = <<-XML
  <?xml version="1.0" encoding="UTF-8"?>
  <feed xmlns="http://www.w3.org/2005/Atom" xml:lang="en">
    <title>The Crystal Programming Language</title>
    <link href="https://crystal-lang.org/" rel="alternate" type="text/html" />
    <entry>
      <title>Crystal 1.21.0 is released!</title>
      <author><name>Johannes Muller</name></author>
      <link href="https://crystal-lang.org/2026/07/16/1.21.0-released/" rel="alternate" type="text/html" />
      <published>2026-07-16T00:00:00+00:00</published>
      <summary type="html">&lt;p&gt;We are announcing a new Crystal release 1.21.0 with several new features and bug fixes.&lt;/p&gt;</summary>
      <content type="html">&lt;p&gt;THE ENTIRE ARTICLE BODY WHICH IS NOT OURS TO HOLD&lt;/p&gt;</content>
    </entry>
    <entry>
      <title>Crystal 1.20.3 is released!</title>
      <author><name>Johannes Muller</name></author>
      <link href="https://crystal-lang.org/2026/05/02/1.20.3-released/" rel="alternate" type="text/html" />
      <published>2026-05-02T00:00:00+00:00</published>
      <summary type="html">A patch release.&lt;script&gt;alert(1)&lt;/script&gt;</summary>
    </entry>
  </feed>
  XML

private def serving(body : String, content_type = "application/xml", &)
  server = HTTP::Server.new do |context|
    context.response.content_type = content_type
    context.response.print body
  end

  address = server.bind_unused_port("127.0.0.1")
  spawn { server.listen }
  Fiber.yield

  begin
    yield "http://127.0.0.1:#{address.port}/feed.xml"
  ensure
    server.close
  end
end

describe CrystalBlogFeed do
  it "names the real feed" do
    CrystalBlogFeed::FEED_URL.should eq("https://crystal-lang.org/feed.xml")
  end

  it "parses an Atom entry into a title, link, author, date and summary" do
    serving(ATOM_FEED) do |url|
      entries = CrystalBlogFeed.fetch(url)

      entries.size.should eq(2)

      first = entries.first
      first.title.should eq("Crystal 1.21.0 is released!")
      first.url.should eq("https://crystal-lang.org/2026/07/16/1.21.0-released/")
      first.author.should eq("Johannes Muller")
      first.published_at.should eq(Time.utc(2026, 7, 16))
      first.summary.should eq("We are announcing a new Crystal release 1.21.0 with several new features and bug fixes.")
    end
  end

  it "sanitises a summary that carries markup" do
    serving(ATOM_FEED) do |url|
      summary = CrystalBlogFeed.fetch(url).last.summary

      summary.should eq("A patch release.")
      summary.downcase.should_not contain("script")
    end
  end

  it "raises a FetchError, not a bare network exception, when unreachable" do
    expect_raises(CrystalBlogFeed::FetchError) do
      CrystalBlogFeed.fetch(UNREACHABLE)
    end
  end

  it "raises a FetchError when the response is not a feed" do
    serving("<html><body>502 Bad Gateway</body></html>", content_type: "text/html") do |url|
      expect_raises(CrystalBlogFeed::FetchError) do
        CrystalBlogFeed.fetch(url)
      end
    end
  end
end

describe CrystalBlogIngest do
  it "stores entries as drafts with their provenance" do
    serving(ATOM_FEED) do |url|
      outcome = CrystalBlogIngest.run(url: url)

      outcome.ok?.should be_true
      outcome.created.should eq(2)

      item = ContentItemQuery.new
        .by_source_url("https://crystal-lang.org/2026/07/16/1.21.0-released/")
        .first

      item.state.should eq(ContentItem::State::DRAFT)
      item.origin.should eq(ContentItem::Origin::CRYSTAL_BLOG)
      item.original_author.should eq("Johannes Muller")
      item.original_published_at.should eq(Time.utc(2026, 7, 16))
      item.attribution.should contain("Johannes Muller")
      item.attribution.should contain("Crystal blog")
      item.license_note.should_not be_nil
    end
  end

  it "keeps the summary and the link but not the article body" do
    serving(ATOM_FEED) do |url|
      CrystalBlogIngest.run(url: url)

      item = ContentItemQuery.new
        .by_source_url("https://crystal-lang.org/2026/07/16/1.21.0-released/")
        .first

      item.body.should be_nil
      item.summary.to_s.should contain("announcing a new Crystal release")

      # Nothing of theirs is held in any column, not just the one we checked.
      ContentItemQuery.new.to_a.each do |row|
        "#{row.body}#{row.summary}".should_not contain("ENTIRE ARTICLE BODY")
      end
    end
  end

  it "does not duplicate when ingestion runs twice" do
    serving(ATOM_FEED) do |url|
      CrystalBlogIngest.run(url: url)
      second = CrystalBlogIngest.run(url: url)

      second.created.should eq(0)
      second.unchanged.should eq(2)
      ContentItemQuery.new.select_count.should eq(2)
    end
  end

  it "keeps ingested entries out of the public index until approved" do
    serving(ATOM_FEED) do |url|
      CrystalBlogIngest.run(url: url)

      ContentItemQuery.new.publicly_visible.select_count.should eq(0)

      response = BrowserClient.exec(News::Index)
      response.status.should eq(HTTP::Status.new(200))
      response.body.should_not contain("Crystal 1.21.0 is released!")
    end
  end

  describe "when the feed cannot be read" do
    it "returns an outcome carrying the error instead of raising" do
      outcome = CrystalBlogIngest.run(url: UNREACHABLE)

      outcome.ok?.should be_false
      outcome.error.should_not be_nil
      outcome.summary.should contain("Feed unavailable")
    end

    it "writes nothing" do
      CrystalBlogIngest.run(url: UNREACHABLE)

      ContentItemQuery.new.select_count.should eq(0)
    end

    it "leaves the public news page rendering" do
      approved = ContentItemFactory.create &.approved.title("Already approved item")

      CrystalBlogIngest.run(url: UNREACHABLE)

      response = BrowserClient.exec(News::Index)

      response.status.should eq(HTTP::Status.new(200))
      response.body.should contain(approved.title)
    end

    it "leaves an already ingested item alone" do
      existing, _ = ContentIngestor.upsert(
        source_url: "https://crystal-lang.org/2026/07/16/1.21.0-released/",
        origin: ContentItem::Origin::CRYSTAL_BLOG,
        title: "Crystal 1.21.0 is released!",
        attribution: "Johannes Muller on the Crystal blog (crystal-lang.org)")

      CrystalBlogIngest.run(url: UNREACHABLE)

      existing.reload.title.should eq("Crystal 1.21.0 is released!")
      ContentItemQuery.new.select_count.should eq(1)
    end
  end
end
