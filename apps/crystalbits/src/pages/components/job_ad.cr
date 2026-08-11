require "../../services/job_ads"

# Paid placement for CrystalGigs, rendered on every page of this site.
#
# The whole component is conditional on having something real to show. There is
# no empty state, no skeleton and no spinner, because all three are ways of
# telling a reader that something is coming when nothing is. If CrystalGigs is
# unreachable, misconfigured, or simply has no open roles, the page renders as
# though this component did not exist.
class JobAd < Lucky::BaseComponent
  needs limit : Int32 = 3

  def render
    ads = CrystalBits::JobAds.current(limit)
    return if ads.empty?

    # A named <aside> is a complementary landmark, so this is listed among the
    # page's regions and can be jumped to or skipped. The name leads with
    # "Advertisement" so nobody has to read the strip to work out that it is
    # one, and names CrystalGigs so it is clear whose jobs these are and that
    # they are not this site's own listings.
    tag "aside",
      class: "job-ad",
      "aria-label": "Advertisement: Crystal jobs from CrystalGigs" do
      div class: "job-ad-head" do
        para class: "job-ad-disclosure" do
          tag "i", class: "fa-solid fa-rectangle-ad job-ad-icon", "aria-hidden": "true"
          text "Advertisement"
        end
        h2 class: "job-ad-heading" do
          text "Crystal jobs from CrystalGigs"
        end
      end

      # No "see all" link. Every job title already goes to CrystalGigs, and a
      # second call to action would mean a second CrystalGigs URL written into
      # this file, which is the deployment fact JOB_ADS_URL exists to keep out
      # of source. Sibling-site navigation belongs in the masthead.
      ul class: "job-ad-list" do
        ads.each { |ad| render_ad(ad) }
      end
    end
  end

  private def render_ad(ad : CrystalBits::JobAds::Ad)
    li class: ad.featured? ? "job-ad-item job-ad-item-featured" : "job-ad-item" do
      # The title is the link, so the link's accessible name is the job title
      # rather than the whole card. One tab stop per job.
      a ad.title, href: ad.url, class: "job-ad-title", rel: "noopener"

      if ad.featured?
        span class: "job-ad-featured" do
          text "Featured"
        end
      end

      para class: "job-ad-meta" do
        span class: "job-ad-company" do
          text ad.company
        end

        if location = ad.location
          span class: "job-ad-location" do
            text location
          end
        end

        if show_remote?(ad)
          span class: "job-ad-remote" do
            text "Remote"
          end
        end
      end
    end
  end

  # A job board's `location` is free text, and on a remote role it very often
  # already reads "Remote" or "Remote (US)". Drawing the flag as well gives
  # the reader "Remote  Remote". The feed is right to send both; deciding not
  # to say it twice is this component's job, not the feed's.
  #
  # Word-boundary matched so a real place name that merely starts with those
  # letters still gets its marker.
  private def show_remote?(ad : CrystalBits::JobAds::Ad) : Bool
    return false unless ad.remote?

    location = ad.location
    return true unless location

    !/\bremote\b/.matches?(location.downcase)
  end
end
