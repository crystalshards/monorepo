require "../spec_helper"

# The Bits strip is the one component on this site whose content comes from
# another service. CrystalBits answering with nothing recent is a real
# answer, and so is a fetch that failed, is backing off, or never ran; both
# render_strip nothing at all, because there is no fallback card and never a
# heading over an empty space.
private BITS_ORIGIN = "https://crystalbits.test"

# A quiet week on CrystalBits. Not a failure: a real, healthy answer.
private def bits_feed_json : String
  %({"posts":[]})
end

private def bits_feed_json(*posts : String) : String
  %({"posts":[#{posts.join(",")}]})
end

private def bits_post_json(title : String, slug = "a-post", excerpt : String? = "A short excerpt.") : String
  %({"title":#{title.to_json},"slug":#{slug.to_json},"excerpt":#{excerpt.to_json}})
end

# Stands in for CrystalBits and counts how often the strip reached for it, so
# the caching and backoff rules are observable rather than assumed.
private class BitsSource
  getter calls = 0

  def initialize(@body : String?, @raises : Exception? = nil)
  end

  def install : BitsSource
    CrystalGigs::BitsFeed.transport = CrystalGigs::BitsFeed::Transport.new do
      @calls += 1
      if error = @raises
        raise error
      end
      @body
    end
    CrystalGigs::BitsFeed.reset!
    self
  end
end

private def bits_source(body : String?) : BitsSource
  BitsSource.new(body).install
end

private def failing_bits_source(error : Exception) : BitsSource
  BitsSource.new(nil, error).install
end

private def render_strip(limit = 3) : String
  BitsStrip.new(limit: limit).render_to_string
end

describe BitsStrip do
  before_each do
    CrystalGigs::BitsFeed.origin = BITS_ORIGIN
  end

  after_each do
    CrystalGigs::BitsFeed.origin = nil
    CrystalGigs::BitsFeed.transport = nil
    CrystalGigs::BitsFeed.reset!
  end

  describe "when the source has articles" do
    it "renders up to three cards with their titles, excerpts and links" do
      bits_source(bits_feed_json(
        bits_post_json("One", slug: "one", excerpt: "First excerpt"),
        bits_post_json("Two", slug: "two", excerpt: "Second excerpt"),
        bits_post_json("Three", slug: "three", excerpt: "Third excerpt"),
        bits_post_json("Four", slug: "four"),
      ))

      html = render_strip
      html.scan(/class="bits-strip-item/).size.should eq(3)
      html.should contain("One")
      html.should contain("First excerpt")
      html.should contain("Three")
      html.should_not contain("Four")
    end

    it "links each card to the configured CrystalBits origin" do
      bits_source(bits_feed_json(bits_post_json("A post", slug: "a-post")))

      html = render_strip
      html.should contain(%(href="#{BITS_ORIGIN}/posts/a-post"))
      # The title is the link, and it leaves this site.
      html.should contain(%(rel="noopener"))
    end

    it "labels itself as CrystalBits' content, in the markup and to a screen reader" do
      bits_source(bits_feed_json(bits_post_json("A post")))

      html = render_strip
      # Visible to everyone, so a reader knows following a card leaves this
      # site before they follow it.
      html.should contain("From our sister site")
      html.should contain("The latest from CrystalBits")
      # And in the landmark's accessible name, so the strip is identifiable
      # as CrystalBits' articles without having to read it.
      html.should contain(%(aria-label="From CrystalBits, our sister site"))
      html.should contain("<aside")
    end

    it "escapes what the source sends rather than trusting it as markup" do
      bits_source(bits_feed_json(bits_post_json(%(<script>alert("x")</script>))))

      html = render_strip
      html.should_not contain("<script>")
      html.should contain("&lt;script&gt;")
    end

    it "renders nothing for a limit of zero, without asking the source" do
      stub = bits_source(bits_feed_json(bits_post_json("A post")))

      render_strip(limit: 0).should be_empty
      stub.calls.should eq(0)
    end
  end

  describe "when the source has nothing usable" do
    it "renders nothing when the feed answers with no posts" do
      bits_source(bits_feed_json)

      render_strip.should be_empty
    end

    it "renders nothing when the fetch comes back with nothing" do
      bits_source(nil)

      render_strip.should be_empty
    end

    it "renders nothing when the source raises instead of answering" do
      # A connection reset, a TLS failure or a read timeout arrives as an
      # exception mid-render_strip. Letting one escape would fail the home page of
      # a site that has nothing to do with CrystalBits.
      failing_bits_source(IO::Error.new("connection reset by peer"))

      render_strip.should be_empty
    end

    it "renders nothing when the feed is not JSON" do
      bits_source("<html>502 Bad Gateway</html>")

      render_strip.should be_empty
    end

    it "renders nothing when the feed is JSON of the wrong shape" do
      bits_source(%({"posts":[{"headline":"A post"}]}))

      render_strip.should be_empty
    end

    it "refuses a hostile slug rather than rendering it" do
      # A javascript: slug is a link too, once composed into one. The feed is
      # first-party, but it is still a network response being written into
      # our markup.
      bits_source(bits_feed_json(
        bits_post_json("Evil", slug: "javascript:alert(1)"),
        bits_post_json("Good", slug: "good-post"),
      ))

      html = render_strip
      html.should_not contain("Evil")
      html.should_not contain("javascript:")
      html.should contain("Good")
      html.scan(/class="bits-strip-item/).size.should eq(1)
    end

    it "refuses slugs that are paths or URLs rather than slugs" do
      bits_source(bits_feed_json(
        bits_post_json("Traversal", slug: "../../admin"),
        bits_post_json("Absolute", slug: "//evil.test/x"),
        bits_post_json("Full URL", slug: "https://evil.test/x"),
      ))

      # Every row was refused, and an answer with nothing usable renders
      # nothing: no heading over an empty space.
      render_strip.should be_empty
    end

    it "leaves the strip working after a failure instead of wedging it" do
      # A failed fetch must release its claim. If it did not, the strip would
      # stay dark for the life of the process rather than recover on the next
      # successful fetch.
      failing_bits_source(IO::Error.new("connection reset by peer"))
      render_strip.should be_empty

      bits_source(bits_feed_json(bits_post_json("Recovered post")))
      render_strip.should contain("Recovered post")
    end
  end

  describe "cost to the page" do
    it "serves later renders from cache instead of the network" do
      stub = bits_source(bits_feed_json(bits_post_json("Cached post")))

      3.times { render_strip.should contain("Cached post") }
      stub.calls.should eq(1)
    end

    it "backs off after a failure instead of paying the timeout per render" do
      stub = failing_bits_source(IO::Error.new("connection reset by peer"))

      3.times { render_strip.should be_empty }
      stub.calls.should eq(1)
    end
  end
end
