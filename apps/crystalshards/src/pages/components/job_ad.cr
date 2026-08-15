require "../../services/job_ads"

# Paid placement for CrystalGigs, rendered on every page of this site.
#
# CrystalGigs' own feed drives this whenever it has real jobs to advertise.
# When it answers with fewer than `limit`, including a genuinely empty board,
# the slot fills the remainder with first-party CrystalGigs house ads rather
# than leaving a gap: an empty board is a real answer CrystalGigs gave, and
# it has earned the right to be advertised on the strength of that answer.
#
# A fetch that failed, is backing off, or never got the chance to run is a
# different thing entirely. It has not established that CrystalGigs, or the
# house ad links this component would build for it, are even reachable, so
# that case renders nothing at all, exactly as it always has. See
# `CrystalShards::JobAds::Answer` for where that line is drawn.
#
# The one other thing that turns the whole strip off is JOB_ADS_URL being
# unset. That is a deliberate switch documented on JobAdsConfig for
# environments that want no ad strip at all, distinct from a feed that ran
# and came back with nothing, so it is respected here rather than papered
# over.
class JobAd < Lucky::BaseComponent
  needs limit : Int32 = 3

  # A CrystalGigs house ad: title plus the path under GIGS_SITE_ORIGIN it
  # sends a reader to. Not a full URL by itself, and never a literal
  # "https://crystalgigs.com" in source: the origin is a deployment fact,
  # read from GigsSiteConfig the same way every other cross-app link in this
  # codebase reads its target rather than hardcoding it.
  private record HouseAd, title : String, path : String

  # One per audience this strip actually serves: a developer looking for
  # Crystal work goes to the job board, a company looking to hire one goes to
  # post a role. Copy only; the honesty is in render_house_ad, which labels
  # every one of these as CrystalGigs' own placement rather than letting the
  # copy alone imply it.
  HOUSE_ADS = [
    HouseAd.new("Browse Crystal jobs on CrystalGigs", "/jobs"),
    HouseAd.new("Post a Crystal role on CrystalGigs", "/jobs/new"),
  ]

  def render
    answer = CrystalShards::JobAds.answer(limit)
    return unless answer.answered?

    ads = answer.ads
    origin = CrystalShards::GigsSiteConfig.origin
    # Nothing to show: the feed answered empty and GIGS_SITE_ORIGIN is not
    # configured (allowed outside production), so there is no house ad to
    # build either.
    return if ads.empty? && origin.nil?

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

        # House ads fill whatever the feed left empty, so the slot always
        # holds exactly `limit` cards. A strip that is sometimes three wide
        # and sometimes one wide, depending on how many real jobs happened to
        # be open, reads as a layout bug rather than an ad rotation. Cycling
        # by position rather than Random.rand keeps a given render's fill
        # identical to the next one: nothing here changes because someone
        # hit reload.
        if origin
          missing = limit - ads.size
          missing.times { |i| render_house_ad(HOUSE_ADS[i % HOUSE_ADS.size], origin) }
        end
      end
    end
  end

  private def render_ad(ad : CrystalShards::JobAds::Ad)
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

  # Same shell as a feed job (job-ad-item, job-ad-title, job-ad-meta) so the
  # slot's shape never depends on where a card came from. The honesty is a
  # visible "First party" label, not just a company field a reader could
  # skim past and mistake for a genuine employer's name.
  private def render_house_ad(ad : HouseAd, origin : String)
    li class: "job-ad-item" do
      a ad.title, href: "#{origin}#{ad.path}", class: "job-ad-title", rel: "noopener"

      para class: "job-ad-meta" do
        span class: "job-ad-company" do
          text "CrystalGigs"
        end
        span class: "job-ad-house" do
          text "First party"
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
  private def show_remote?(ad : CrystalShards::JobAds::Ad) : Bool
    return false unless ad.remote?

    location = ad.location
    return true unless location

    !/\bremote\b/.matches?(location.downcase)
  end
end
