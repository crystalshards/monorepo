require "../spec_helper"

# The ad strip is the one component on this site whose content comes from
# another service. Every way that service can let us down has to end in the
# same place: no markup at all. An empty box, a "no jobs right now" line or a
# spinner would each be this site telling a reader something about CrystalGigs
# that this site does not actually know.
private ENDPOINT = URI.parse("http://job-ads.test/api/ads")

# A board with nothing to advertise. Not a failure: a real, healthy answer.
private def feed : String
  %({"jobs":[]})
end

private def feed(*jobs : String) : String
  %({"jobs":[#{jobs.join(",")}]})
end

private def job(title : String, company = "Crystal Corp", location : String? = "Denver, CO",
                remote = false, featured = false, url = "https://crystalgigs.test/jobs/1") : String
  %({"title":#{title.to_json},"company":#{company.to_json},"location":#{location.to_json},) +
    %("remote":#{remote},"featured":#{featured},"url":#{url.to_json}})
end

# Stands in for CrystalGigs and counts how often the strip reached for it, so
# the caching and backoff rules are observable rather than assumed.
private class Source
  getter calls = 0

  def initialize(@body : String?, @raises : Exception? = nil)
  end

  def install : Source
    CrystalBits::JobAds.transport = CrystalBits::JobAds::Transport.new do
      @calls += 1
      if error = @raises
        raise error
      end
      @body
    end
    CrystalBits::JobAds.reset!
    self
  end
end

private def source(body : String?) : Source
  Source.new(body).install
end

private def failing_source(error : Exception) : Source
  Source.new(nil, error).install
end

private def render(limit = 3) : String
  JobAd.new(limit: limit).render_to_string
end

describe JobAd do
  before_each do
    CrystalBits::JobAdsConfig.endpoint = ENDPOINT
  end

  after_each do
    CrystalBits::JobAdsConfig.endpoint = nil
    CrystalBits::JobAds.transport = nil
    CrystalBits::JobAds.reset!
  end

  # The most likely production breakage: CrystalGigs is down, slow, or
  # returning something unreadable, on a site that has nothing to do with
  # CrystalGigs. None of it may reach the page.
  describe "when the source cannot be used" do
    it "renders nothing when the fetch comes back with nothing" do
      source(nil)

      render.should be_empty
    end

    it "renders nothing when the source raises instead of answering" do
      # A connection reset, a TLS failure or a read timeout arrives as an
      # exception mid-render. This component is mounted in MainLayout, so
      # letting one escape would 500 every page on the site over an ad.
      failing_source(IO::Error.new("connection reset by peer"))

      render.should be_empty
    end

    it "renders nothing when an unexpected error escapes the source" do
      # Not IO::Error, not one of the network types the HTTP path names. The
      # rule is the failure mode, not the exception class.
      failing_source(ArgumentError.new("something nobody predicted"))

      render.should be_empty
    end

    it "renders nothing when the feed is not JSON" do
      source("<html>502 Bad Gateway</html>")

      render.should be_empty
    end

    it "renders nothing when the feed is JSON of the wrong shape" do
      source(%({"jobs":[{"headline":"Senior Crystal Developer"}]}))

      render.should be_empty
    end

    it "renders nothing when the board has no jobs to advertise" do
      source(feed)

      render.should be_empty
    end

    it "renders nothing when the strip is not configured" do
      source(feed(job("Senior Crystal Developer")))
      CrystalBits::JobAdsConfig.endpoint = nil

      render.should be_empty
    end

    it "renders nothing rather than an unsafe link" do
      # A javascript: href is a link too. The feed is first-party, but it is
      # still a network response being written into our markup.
      source(feed(job("Senior Crystal Developer", url: "javascript:alert(1)")))

      render.should be_empty
    end

    it "keeps the good rows when only some links are unsafe" do
      source(feed(
        job("Bad role", url: "javascript:alert(1)"),
        job("Good role", url: "https://crystalgigs.test/jobs/2"),
      ))

      html = render
      html.should_not contain("Bad role")
      html.should contain("Good role")
    end

    it "leaves the strip working after a failure instead of wedging it" do
      # A failed fetch must release its claim. If it did not, the strip would
      # go dark for the life of the process and look exactly like a job board
      # with nothing to advertise.
      failing_source(IO::Error.new("connection reset by peer"))
      render.should be_empty

      source(feed(job("Recovered role")))
      render.should contain("Recovered role")
    end
  end

  describe "when the source has jobs" do
    it "renders each job with its title as the link" do
      source(feed(job("Senior Crystal Developer", url: "https://crystalgigs.test/jobs/7")))

      html = render
      html.should contain("Senior Crystal Developer")
      html.should contain(%(href="https://crystalgigs.test/jobs/7"))
      html.should contain("Crystal Corp")
      html.should contain("Denver, CO")
    end

    it "labels itself as advertising, in the markup and to a screen reader" do
      source(feed(job("Senior Crystal Developer")))

      html = render
      # Visible to everyone.
      html.should contain("Advertisement")
      # And in the landmark's accessible name, so the strip is identifiable as
      # an ad, and as CrystalGigs' jobs rather than this site's, without
      # having to read it.
      html.should contain(%(aria-label="Advertisement: Crystal jobs from CrystalGigs"))
      html.should contain("<aside")
    end

    it "keeps the order the source sent, so featured placement is not undone here" do
      source(feed(
        job("Featured role", featured: true, url: "https://crystalgigs.test/jobs/1"),
        job("Plain role", url: "https://crystalgigs.test/jobs/2"),
      ))

      html = render
      html.index("Featured role").not_nil!.should be < html.index("Plain role").not_nil!
    end

    it "marks featured placements rather than passing them off as ordinary" do
      source(feed(job("Paid role", featured: true)))

      html = render
      html.should contain("job-ad-item-featured")
      html.should contain("Featured")
    end

    it "shows Remote only for remote roles" do
      source(feed(job("Remote role", location: "Denver, CO", remote: true)))
      render.should contain("job-ad-remote")

      source(feed(job("Onsite role", location: "Denver, CO", remote: false)))
      render.should_not contain("job-ad-remote")
    end

    it "does not say Remote twice when the location already says it" do
      # A job board's location is free text and very often reads "Remote" on a
      # remote role, which rendered as "Remote  Remote" until the marker
      # learned to stand down.
      source(feed(job("Remote role", location: "Remote", remote: true)))

      html = render
      html.should_not contain("job-ad-remote")
      html.scan("Remote").size.should eq(2) # the title and the location, once each
    end

    it "stands down for a location that only mentions remote" do
      source(feed(job("Hybrid role", location: "Denver, CO (Remote)", remote: true)))

      render.should_not contain("job-ad-remote")
    end

    it "still marks a place name that merely starts with those letters" do
      # "Remoteville" is a location, not a working arrangement.
      source(feed(job("Small town role", location: "Remoteville, OH", remote: true)))

      render.should contain("job-ad-remote")
    end

    it "omits location entirely when the job has none" do
      source(feed(job("Anywhere role", location: nil)))

      html = render
      html.should contain("Anywhere role")
      html.should_not contain("job-ad-location")
    end

    it "renders at most the requested number of jobs" do
      source(feed(
        job("One", url: "https://crystalgigs.test/jobs/1"),
        job("Two", url: "https://crystalgigs.test/jobs/2"),
        job("Three", url: "https://crystalgigs.test/jobs/3"),
        job("Four", url: "https://crystalgigs.test/jobs/4"),
        job("Five", url: "https://crystalgigs.test/jobs/5"),
      ))

      html = render(limit: 3)
      html.scan(/class="job-ad-item/).size.should eq(3)
      html.should contain("Three")
      html.should_not contain("Four")
    end

    it "renders nothing for a limit of zero, without asking the source" do
      stub = source(feed(job("Any role")))

      render(limit: 0).should be_empty
      stub.calls.should eq(0)
    end

    it "escapes what the source sends rather than trusting it as markup" do
      source(feed(job(%(<script>alert("x")</script>))))

      html = render
      html.should_not contain("<script>")
      html.should contain("&lt;script&gt;")
    end
  end

  describe "cost to the page" do
    it "serves later renders from cache instead of the network" do
      stub = source(feed(job("Cached role")))

      3.times { render.should contain("Cached role") }

      stub.calls.should eq(1)
    end

    it "stands down after a failure instead of retrying on every page view" do
      stub = source(nil)

      6.times { render.should be_empty }

      # One attempt, then the backoff window. A site whose ad source is down
      # must not also spend a socket and a timeout on every single render.
      stub.calls.should eq(1)
    end

    it "caches an empty board too, so an idle job board is not a retry loop" do
      stub = source(feed)

      3.times { render.should be_empty }

      stub.calls.should eq(1)
    end
  end

  describe "cache invalidation" do
    it "drops what it had when a later fetch fails" do
      # Explicitly preferred over serving stale ads: once we can no longer
      # confirm a role is open, we stop advertising it.
      source(feed(job("Open role")))
      render.should contain("Open role")

      source(nil)
      render.should be_empty
    end
  end
end
