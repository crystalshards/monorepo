# Writes ingested and generated items into the editorial queue.
#
# Two rules hold for every write that happens here, and they are the reason
# this is one class rather than logic repeated in each source:
#
#   1. New rows land in DRAFT. Nothing this class writes is ever public.
#   2. An existing row's `state` is never touched. Re-running ingestion
#      refreshes a headline or a summary; it cannot resurrect something an
#      editor rejected, and it cannot quietly retract something they approved.
class ContentIngestor
  enum Change
    Created
    Updated
    Unchanged
  end

  record Outcome, created : Int32, updated : Int32, unchanged : Int32, failed : Int32 do
    def total : Int32
      created + updated + unchanged + failed
    end

    def summary : String
      "#{created} new, #{updated} refreshed, #{unchanged} unchanged, #{failed} failed"
    end
  end

  class Tally
    getter created = 0
    getter updated = 0
    getter unchanged = 0
    getter failed = 0

    def record(change : Change) : Nil
      case change
      in Change::Created   then @created += 1
      in Change::Updated   then @updated += 1
      in Change::Unchanged then @unchanged += 1
      end
    end

    def record_failure : Nil
      @failed += 1
    end

    def outcome : Outcome
      Outcome.new(created: @created, updated: @updated, unchanged: @unchanged, failed: @failed)
    end
  end

  # `source_url` is the deduplication key and is required. Anything without a
  # stable source URL is not something we can ingest twice safely, so it does
  # not belong on this path.
  def self.upsert(
    source_url : String,
    origin : String,
    title : String,
    attribution : String,
    summary : String? = nil,
    body : String? = nil,
    original_author : String? = nil,
    original_published_at : Time? = nil,
    license_note : String? = nil,
    machine_drafted : Bool = false,
    source_urls : Array(String) = [] of String,
  ) : {ContentItem, Change}
    if existing = ContentItemQuery.new.by_source_url(source_url).first?
      return refresh(existing,
        title: title,
        summary: summary,
        body: body,
        attribution: attribution,
        original_author: original_author,
        original_published_at: original_published_at,
        license_note: license_note,
        source_urls: source_urls)
    end

    item = ContentItem::SaveOperation.create!(
      origin: origin,
      state: ContentItem::State::DRAFT,
      title: title,
      slug: ContentSlug.generate(title),
      body: body,
      summary: summary,
      source_url: source_url,
      original_author: original_author,
      original_published_at: original_published_at || Time.utc,
      attribution: attribution,
      license_note: license_note,
      machine_drafted: machine_drafted,
      source_urls: source_urls,
    )

    {item, Change::Created}
  end

  private def self.refresh(
    item : ContentItem,
    title : String,
    summary : String?,
    body : String?,
    attribution : String,
    original_author : String?,
    original_published_at : Time?,
    license_note : String?,
    source_urls : Array(String),
  ) : {ContentItem, Change}
    changed = item.title != title ||
              item.summary != summary ||
              item.body != body ||
              item.attribution != attribution ||
              item.original_author != original_author ||
              item.license_note != license_note ||
              item.source_urls != source_urls

    return {item, Change::Unchanged} unless changed

    # Note what is absent: state, slug, source_url, origin, machine_drafted,
    # reviewed_at, reviewed_by. A refresh updates what the source says, not
    # what an editor decided about it, and not the URL a reader may have.
    updated = ContentItem::SaveOperation.update!(item,
      title: title,
      summary: summary,
      body: body,
      attribution: attribution,
      original_author: original_author,
      original_published_at: original_published_at || item.original_published_at,
      license_note: license_note,
      source_urls: source_urls,
    )

    {updated, Change::Updated}
  end
end
