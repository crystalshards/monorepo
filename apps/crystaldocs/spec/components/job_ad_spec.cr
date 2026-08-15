require "../spec_helper"

# The ad strip is the one component on this site whose content comes from
# another service. CrystalGigs answering with fewer jobs than the slot holds,
# including a genuinely empty board, is a real answer: the strip fills the
# remainder with first-party CrystalGigs house ads rather than leaving a gap.
# A fetch that failed, is backing off, or never ran is different: it has not
# established that CrystalGigs, or the house ad links built from it, are even
# reachable, so that case renders nothing at all, the same as it always has.
private ENDPOINT = URI.parse("http://job-ads.test/api/ads")
# Deliberately a different domain than the crystalgigs.test feed job stubs
# below, so an assertion scanning for one can never accidentally match the
# other.
private GIGS_ORIGIN = "https://crystalgigs.com"

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
    CrystalDocs::JobAds.transport = CrystalDocs::JobAds::Transport.new do
      @calls += 1
      if error = @raises
        raise error
      end
      @body
    end
    CrystalDocs::JobAds.reset!
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
  Components::JobAd.new(limit: limit).render_to_string
end

describe Components::JobAd do
  before_each do
    CrystalDocs::JobAdsConfig.endpoint = ENDPOINT
    CrystalDocs::GigsSiteConfig.origin = GIGS_ORIGIN
  end

  after_each do
    CrystalDocs::JobAdsConfig.endpoint = nil
    CrystalDocs::JobAds.transport = nil
    CrystalDocs::JobAds.reset!
    CrystalDocs::GigsSiteConfig.origin = nil
  end

  # The most likely production breakage: CrystalGigs is down, slow, or
  # returning something unreadable, on a site that has nothing to do with
  # CrystalGigs. A fetch that fails this way has not established that
  # CrystalGigs, or the house ad links this component would build for it, are
  # even reachable. None of it may reach the page: not a real ad, and not a
  # house ad standing in for one.
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

    it "falls back to a house ad when the board has no jobs to advertise" do
      # Unlike the failures above, this is CrystalGigs answering: a healthy
      # board that happens to be empty right now. That answer has earned the
      # right to be advertised on its own strength.
      source(feed)

      html = render
      html.should contain(%(href="#{GIGS_ORIGIN}/jobs"))
      html.should contain("First party")
      # The slot still holds three cards; a healthy empty board is not a
      # reason to render a strip that is visibly smaller than usual.
      html.scan(/class="job-ad-item/).size.should eq(3)
    end

    it "renders nothing when the strip is not configured" do
      # JOB_ADS_URL unset is a deliberate switch documented on JobAdsConfig
      # for environments that want no ad strip at all. It is not the same
      # thing as a feed that ran and came back with nothing, so house ads do
      # not fill in for it: an environment that asked for no strip gets none.
      source(feed(job("Senior Crystal Developer")))
      CrystalDocs::JobAdsConfig.endpoint = nil

      render.should be_empty
    end

    it "falls back to a house ad rather than an unsafe link" do
      # A javascript: href is a link too. The feed is first-party, but it is
      # still a network response being written into our markup. Filtering it
      # out still leaves this a successful, if now empty, answer.
      source(feed(job("Senior Crystal Developer", url: "javascript:alert(1)")))

      html = render
      html.should_not contain("javascript:")
      html.should contain(%(href="#{GIGS_ORIGIN}/jobs"))
    end

    it "keeps the good rows when only some links are unsafe, and fills the rest" do
      source(feed(
        job("Bad role", url: "javascript:alert(1)"),
        job("Good role", url: "https://crystalgigs.test/jobs/2"),
      ))

      html = render
      html.should_not contain("Bad role")
      html.should contain("Good role")
      # One real job survived the filter; house ads fill the other two seats.
      html.scan(/class="job-ad-item/).size.should eq(3)
    end

    it "leaves the strip working after a failure instead of wedging it" do
      # A failed fetch must release its claim. If it did not, the strip would
      # stay dark for the life of the process rather than recover on the next
      # successful fetch.
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

      # A healthy empty board is a successful answer, so it fills with house
      # ads on every one of these renders, all served from the same cached
      # answer rather than a fresh fetch each time.
      3.times { render.should contain(%(href="#{GIGS_ORIGIN}/jobs")) }

      stub.calls.should eq(1)
    end
  end

  describe "cache invalidation" do
    it "drops what it had when a later fetch fails" do
      # Explicitly preferred over serving stale ads: once we can no longer
      # confirm a role is open, we stop advertising it. The later failure has
      # not established CrystalGigs is reachable either, so nothing renders
      # in its place, not even a house ad.
      source(feed(job("Open role")))
      render.should contain("Open role")

      source(nil)
      render.should be_empty
    end
  end

  # The things the assignment asked to be proven directly: a house ad shows
  # up when the feed genuinely answers empty, the slot's card count is stable
  # across every way the feed can answer, a failed fetch still renders
  # nothing at all, and every house ad points at the audience-specific route
  # under the configured GIGS_SITE_ORIGIN rather than a literal.
  describe "house ads" do
    it "renders a house ad when the feed is empty" do
      source(feed)

      html = render
      html.should contain(%(href="#{GIGS_ORIGIN}/jobs"))
      html.should contain("First party")
    end

    it "keeps the card count at the requested limit whenever the feed answers" do
      source(feed)
      render.scan(/class="job-ad-item/).size.should eq(3)

      source(feed(job("One")))
      render.scan(/class="job-ad-item/).size.should eq(3)

      source(feed(job("One"), job("Two"), job("Three")))
      render.scan(/class="job-ad-item/).size.should eq(3)
    end

    it "renders zero cards, not a padded strip, when the feed fails" do
      # A failed fetch is not "an empty answer worth padding out": it is no
      # answer at all, so the count guarantee above does not apply to it.
      source(nil)

      render.scan(/class="job-ad-item/).size.should eq(0)
      render.should be_empty
    end

    it "fills only the seats the feed left empty" do
      source(feed(job("Real role", url: "https://crystalgigs.test/jobs/9")))

      html = render
      html.should contain("Real role")
      html.scan(GIGS_ORIGIN).size.should eq(2)
    end

    it "points each house ad at its own route under GIGS_SITE_ORIGIN, with no tracking parameters" do
      source(feed)

      html = render(limit: 2)
      # Verified live on the CrystalGigs app: GET /jobs lists roles, GET
      # /jobs/new is where a company posts one.
      html.should contain(%(href="#{GIGS_ORIGIN}/jobs"))
      html.should contain(%(href="#{GIGS_ORIGIN}/jobs/new"))
      html.should_not contain("utm_")
    end

    it "alternates between the two audiences instead of repeating one" do
      source(feed)

      html = render(limit: 2)
      html.should contain("Browse Crystal jobs on CrystalGigs")
      html.should contain("Post a Crystal role on CrystalGigs")
    end

    it "fills the same way on the next render, so a reload does not reshuffle it" do
      source(feed)

      render.should eq(render)
    end

    it "labels a house ad as CrystalGigs' own rather than a specific employer" do
      source(feed)

      html = render
      html.should contain("CrystalGigs")
      html.should contain("First party")
      html.should_not contain("job-ad-item-featured")
    end

    it "renders only the real jobs it has, not padded with house ads, when GIGS_SITE_ORIGIN is unset" do
      # Allowed outside production. There is no origin to build a house ad
      # link from, so the strip shows what CrystalGigs actually sent and
      # nothing more.
      CrystalDocs::GigsSiteConfig.origin = nil
      source(feed(job("Only role")))

      html = render
      html.should contain("Only role")
      html.scan(/class="job-ad-item/).size.should eq(1)
    end

    it "renders nothing when the board is empty and GIGS_SITE_ORIGIN is unset" do
      CrystalDocs::GigsSiteConfig.origin = nil
      source(feed)

      render.should be_empty
    end
  end
end
