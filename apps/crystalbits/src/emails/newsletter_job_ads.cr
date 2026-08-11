require "html"
require "../services/job_ads"

module CrystalBits
  # The CrystalGigs job block for the newsletter.
  #
  # Email is not the web. Three constraints shape everything below and none of
  # them are negotiable:
  #
  # - Nothing may depend on public/css/app.css. A subscriber's mail client
  #   never loads it, and Gmail strips <style> blocks from forwarded mail. So
  #   every rule is an inline style attribute and every colour is a literal.
  #   `var(--accent)` renders as nothing at all in most clients, which is why
  #   the palette is repeated here as hex rather than referenced as tokens.
  # - Layout is tables. Flexbox and grid are unusable in Outlook, which still
  #   renders through Word.
  # - Links are absolute, because there is no page to be relative to.
  #
  # The honesty rule from the on-site strip carries over unchanged: no jobs
  # means no block. A newsletter that says "no jobs this week" when the truth
  # is that we could not reach CrystalGigs is a newsletter that lies.
  module NewsletterJobAds
    # Up to three. A newsletter is someone's inbox, not a job board.
    MAX_JOBS = 3

    # Mirrors the Mineral tokens, flattened to literals because email cannot
    # resolve custom properties. Keep these in step with the garnet palette in
    # public/css/app.css if that palette moves.
    INK         = "#0e1416"
    INK_MUTED   = "#55666b" # 5.28:1 on SUNK
    SURFACE     = "#ffffff"
    SUNK        = "#eef1f1"
    EDGE        = "#d8dfe0"
    EDGE_STRONG = "#98a7aa"
    ACCENT      = "#96233a" # 8.08:1 on SURFACE

    SANS = "'IBM Plex Sans', -apple-system, 'Segoe UI', Helvetica, Arial, sans-serif"

    # An inline-styled HTML fragment, or an empty string when there is nothing
    # honest to show. Callers can concatenate it unconditionally.
    def self.html(limit : Int32 = MAX_JOBS) : String
      ads = jobs(limit)
      return "" if ads.empty?

      String.build do |io|
        io << %(<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" )
        io << %(style="width:100%;border-collapse:collapse;background:#{SUNK};)
        io << %(border:1px solid #{EDGE};border-top:2px solid #{EDGE_STRONG};margin:24px 0;">)
        io << %(<tr><td style="padding:18px 20px 20px 20px;font-family:#{SANS};">)

        # The disclosure is first, in the reading order, before the offer.
        io << %(<p style="margin:0 0 4px 0;font-size:12px;line-height:1.2;font-weight:700;)
        io << %(letter-spacing:0.09em;text-transform:uppercase;color:#{INK_MUTED};">Advertisement</p>)
        io << %(<p style="margin:0 0 14px 0;font-size:18px;line-height:1.25;font-weight:700;)
        io << %(color:#{INK};">Crystal jobs from CrystalGigs</p>)

        ads.each { |ad| html_job(io, ad) }

        io << %(</td></tr></table>)
      end
    end

    # The plain-text alternative. A multipart email that only fills in the HTML
    # part shows subscribers on text-only clients an empty message, so this is
    # part of the deliverable rather than a nicety.
    def self.text(limit : Int32 = MAX_JOBS) : String
      ads = jobs(limit)
      return "" if ads.empty?

      String.build do |io|
        io << "ADVERTISEMENT\n"
        io << "Crystal jobs from CrystalGigs\n\n"

        ads.each do |ad|
          io << "* " << ad.title
          io << " (Featured)" if ad.featured?
          io << "\n  " << facts(ad).join(" / ") << "\n"
          io << "  " << ad.url << "\n\n"
        end
      end
    end

    private def self.jobs(limit : Int32) : Array(JobAds::Ad)
      JobAds.current(limit.clamp(0, MAX_JOBS))
    end

    private def self.html_job(io : IO, ad : JobAds::Ad) : Nil
      io << %(<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" )
      io << %(style="width:100%;border-collapse:collapse;margin:0 0 10px 0;"><tr>)
      io << %(<td style="padding:12px 14px;background:#{SURFACE};border:1px solid #{EDGE};)
      # The featured marker is a border rather than a chip, because a chip
      # relies on padding and background rendering that Outlook does not
      # reliably give an inline element.
      io << %(border-left:3px solid #{ACCENT};) if ad.featured?
      io << %(">)

      io << %(<a href="#{HTML.escape(ad.url)}" )
      io << %(style="font-family:#{SANS};font-size:16px;line-height:1.3;font-weight:600;)
      io << %(color:#{INK};text-decoration:underline;">)
      io << HTML.escape(ad.title)
      io << %(</a>)

      if ad.featured?
        io << %(<span style="font-family:#{SANS};font-size:12px;font-weight:600;color:#{ACCENT};)
        io << %(margin-left:8px;">Featured</span>)
      end

      io << %(<p style="margin:4px 0 0 0;font-family:#{SANS};font-size:13px;line-height:1.4;)
      io << %(color:#{INK_MUTED};">)
      facts(ad).each_with_index do |fact, index|
        # Hidden from assistive tech where it is honoured, so the line reads as
        # facts rather than punctuation. Harmless in clients that ignore it.
        io << %( <span aria-hidden="true">&#183;</span> ) if index > 0
        io << HTML.escape(fact)
      end
      io << %(</p></td></tr></table>)
    end

    private def self.facts(ad : JobAds::Ad) : Array(String)
      facts = [ad.company]
      if location = ad.location
        facts << location
      end
      facts << "Remote" if show_remote?(ad)
      facts
    end

    # A job board's `location` is free text, and on a remote role it very
    # often already reads "Remote" or "Remote (US)". Adding the flag as well
    # gives the reader "Remote / Remote". Word-boundary matched so a real
    # place name that merely starts with those letters keeps its marker.
    private def self.show_remote?(ad : JobAds::Ad) : Bool
      return false unless ad.remote?

      location = ad.location
      return true unless location

      !/\bremote\b/.matches?(location.downcase)
    end
  end
end
