require "../spec_helper"

private ENDPOINT = URI.parse("http://job-ads.test/api/ads")

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

private def source(body : String?)
  CrystalBits::JobAds.transport = CrystalBits::JobAds::Transport.new { body }
  CrystalBits::JobAds.reset!
end

describe CrystalBits::NewsletterJobAds do
  before_each do
    CrystalBits::JobAdsConfig.endpoint = ENDPOINT
  end

  after_each do
    CrystalBits::JobAdsConfig.endpoint = nil
    CrystalBits::JobAds.transport = nil
    CrystalBits::JobAds.reset!
  end

  # Same rule as the on-site strip. A newsletter that says "no jobs this week"
  # when the truth is that we could not reach CrystalGigs is a newsletter that
  # lies, and unlike a web page it cannot be corrected after it is sent.
  describe "when there is nothing honest to show" do
    it "renders an empty string when the source fails" do
      source(nil)

      CrystalBits::NewsletterJobAds.html.should be_empty
      CrystalBits::NewsletterJobAds.text.should be_empty
    end

    it "renders an empty string when the board has no jobs" do
      source(feed)

      CrystalBits::NewsletterJobAds.html.should be_empty
      CrystalBits::NewsletterJobAds.text.should be_empty
    end

    it "renders an empty string when the strip is not configured" do
      source(feed(job("Senior Crystal Developer")))
      CrystalBits::JobAdsConfig.endpoint = nil

      CrystalBits::NewsletterJobAds.html.should be_empty
      CrystalBits::NewsletterJobAds.text.should be_empty
    end
  end

  describe "the HTML block" do
    it "carries at most three jobs, whatever the caller asks for" do
      source(feed(
        job("One", url: "https://crystalgigs.test/jobs/1"),
        job("Two", url: "https://crystalgigs.test/jobs/2"),
        job("Three", url: "https://crystalgigs.test/jobs/3"),
        job("Four", url: "https://crystalgigs.test/jobs/4"),
      ))

      html = CrystalBits::NewsletterJobAds.html(limit: 10)

      html.should contain("One")
      html.should contain("Three")
      html.should_not contain("Four")
    end

    it "keeps the order the source sent" do
      source(feed(
        job("Featured role", featured: true, url: "https://crystalgigs.test/jobs/1"),
        job("Plain role", url: "https://crystalgigs.test/jobs/2"),
      ))

      html = CrystalBits::NewsletterJobAds.html
      html.index("Featured role").not_nil!.should be < html.index("Plain role").not_nil!
    end

    it "labels itself as advertising" do
      source(feed(job("Senior Crystal Developer")))

      html = CrystalBits::NewsletterJobAds.html
      html.should contain("Advertisement")
      html.should contain("Crystal jobs from CrystalGigs")
    end

    it "needs no site CSS: every rule is inline and every colour is a literal" do
      source(feed(job("Senior Crystal Developer", featured: true)))

      html = CrystalBits::NewsletterJobAds.html
      # A mail client never loads app.css, and most strip <style> blocks.
      html.should_not contain("<style")
      html.should_not contain("class=")
      # Custom properties resolve to nothing in almost every mail client.
      html.should_not contain("var(--")
      html.should contain(%(style="))
      html.should contain(CrystalBits::NewsletterJobAds::ACCENT)
    end

    it "lays out with presentation tables, which is what Outlook can render" do
      source(feed(job("Senior Crystal Developer")))

      html = CrystalBits::NewsletterJobAds.html
      html.should contain("<table")
      # Marked presentational so a screen reader does not announce the layout
      # scaffolding as a data table.
      html.should contain(%(role="presentation"))
      html.should_not contain("display:flex")
      html.should_not contain("display:grid")
    end

    it "links absolutely, because an email has no page to be relative to" do
      source(feed(job("Senior Crystal Developer", url: "https://crystalgigs.test/jobs/7")))

      CrystalBits::NewsletterJobAds.html
        .should contain(%(href="https://crystalgigs.test/jobs/7"))
    end

    it "escapes what the source sends rather than trusting it as markup" do
      source(feed(job(%(<script>alert("x")</script>), company: %(Ampersand & Co))))

      html = CrystalBits::NewsletterJobAds.html
      html.should_not contain("<script>")
      html.should contain("&lt;script&gt;")
      html.should contain("Ampersand &amp; Co")
    end

    it "drops jobs whose link is not a safe scheme" do
      source(feed(job("Bad role", url: "javascript:alert(1)")))

      CrystalBits::NewsletterJobAds.html.should be_empty
    end
  end

  describe "the plain-text alternative" do
    it "carries the same jobs, so a text-only client is not sent a blank part" do
      source(feed(
        job("Senior Crystal Developer", location: "Denver, CO", remote: true,
          url: "https://crystalgigs.test/jobs/7"),
      ))

      text = CrystalBits::NewsletterJobAds.text
      text.should contain("ADVERTISEMENT")
      text.should contain("Senior Crystal Developer")
      text.should contain("Crystal Corp")
      text.should contain("Denver, CO")
      text.should contain("Remote")
      text.should contain("https://crystalgigs.test/jobs/7")
      text.should_not contain("<")
    end

    it "caps at three like the HTML block" do
      source(feed(
        job("One", url: "https://crystalgigs.test/jobs/1"),
        job("Two", url: "https://crystalgigs.test/jobs/2"),
        job("Three", url: "https://crystalgigs.test/jobs/3"),
        job("Four", url: "https://crystalgigs.test/jobs/4"),
      ))

      text = CrystalBits::NewsletterJobAds.text(limit: 10)
      text.should contain("Three")
      text.should_not contain("Four")
    end

    it "omits location when the job has none" do
      source(feed(job("Anywhere role", location: nil, remote: true)))

      CrystalBits::NewsletterJobAds.text.should contain("Crystal Corp / Remote")
    end

    it "does not say Remote twice when the location already says it" do
      source(feed(job("Remote role", location: "Remote", remote: true)))

      text = CrystalBits::NewsletterJobAds.text
      text.should contain("Crystal Corp / Remote")
      text.should_not contain("Remote / Remote")
    end
  end
end
