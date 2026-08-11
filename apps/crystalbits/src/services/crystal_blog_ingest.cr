# Pulls the Crystal blog feed into the editorial queue as drafts.
#
# The whole thing is written so that a failure is a reported non-event. A DNS
# outage, a 502 from crystal-lang.org or a malformed document produces an
# Outcome carrying an error string and zero writes; it never propagates an
# exception into a page render.
class CrystalBlogIngest
  ATTRIBUTION_SUFFIX = "on the Crystal blog (crystal-lang.org)"

  LICENSE_NOTE = "Headline, summary and link only, reproduced from the public " \
                 "crystal-lang.org Atom feed. The full article stays on the Crystal " \
                 "blog and its rights remain with its authors."

  record Outcome,
    created : Int32,
    updated : Int32,
    unchanged : Int32,
    failed : Int32,
    error : String? do
    def ok? : Bool
      error.nil?
    end

    def summary : String
      return "Feed unavailable: #{error}" if error
      "#{created} new, #{updated} refreshed, #{unchanged} unchanged, #{failed} failed"
    end
  end

  def self.run(url : String = CrystalBlogFeed::FEED_URL, limit : Int32 = 20) : Outcome
    new(url, limit).run
  end

  def initialize(@url : String = CrystalBlogFeed::FEED_URL, @limit : Int32 = 20)
  end

  def run : Outcome
    entries = begin
      CrystalBlogFeed.fetch(@url)
    rescue ex : CrystalBlogFeed::FetchError
      Log.for("crystalbits.ingest").warn { "Crystal blog feed unavailable: #{ex.message}" }
      return Outcome.new(created: 0, updated: 0, unchanged: 0, failed: 0, error: ex.message)
    end

    tally = ContentIngestor::Tally.new

    entries.first(@limit).each do |entry|
      begin
        _, change = ContentIngestor.upsert(
          source_url: entry.url,
          origin: ContentItem::Origin::CRYSTAL_BLOG,
          title: entry.title,
          summary: entry.summary.presence,
          # No body on purpose. We hold a headline, a summary and a link; the
          # article itself is theirs and stays on their site.
          body: nil,
          attribution: attribution_for(entry),
          original_author: entry.author,
          original_published_at: entry.published_at,
          license_note: LICENSE_NOTE,
        )
        tally.record(change)
      rescue ex
        Log.for("crystalbits.ingest").warn { "Skipped feed entry #{entry.url}: #{ex.message}" }
        tally.record_failure
      end
    end

    result = tally.outcome

    Outcome.new(
      created: result.created,
      updated: result.updated,
      unchanged: result.unchanged,
      failed: result.failed,
      error: nil,
    )
  end

  private def attribution_for(entry : CrystalBlogFeed::Entry) : String
    if author = entry.author.presence
      "#{author} #{ATTRIBUTION_SUFFIX}"
    else
      "Published #{ATTRIBUTION_SUFFIX}"
    end
  end
end
