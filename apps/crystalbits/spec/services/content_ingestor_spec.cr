require "../spec_helper"

private SOURCE = "https://crystal-lang.org/2026/07/16/1.21.0-released/"

private def ingest(title = "Crystal 1.21.0 is released!", summary = "A new release.")
  ContentIngestor.upsert(
    source_url: SOURCE,
    origin: ContentItem::Origin::CRYSTAL_BLOG,
    title: title,
    summary: summary,
    attribution: "Johannes Muller on the Crystal blog (crystal-lang.org)",
    original_author: "Johannes Muller",
    original_published_at: Time.utc(2026, 7, 16),
    license_note: "Headline, summary and link only.",
  )
end

describe ContentIngestor do
  it "creates ingested items in a draft state, never public" do
    item, change = ingest

    change.should eq(ContentIngestor::Change::Created)
    item.state.should eq(ContentItem::State::DRAFT)
    item.publicly_visible?.should be_false
    ContentItemQuery.new.publicly_visible.select_count.should eq(0)
  end

  it "does not create a second copy when ingestion runs again" do
    ingest
    ingest
    ingest

    ContentItemQuery.new.by_source_url(SOURCE).select_count.should eq(1)
    ContentItemQuery.new.select_count.should eq(1)
  end

  it "reports an unchanged re-run rather than rewriting the row" do
    first, _ = ingest
    second, change = ingest

    change.should eq(ContentIngestor::Change::Unchanged)
    second.id.should eq(first.id)
    second.updated_at.should eq(first.updated_at)
  end

  it "refreshes a headline that changed at the source" do
    original, _ = ingest
    updated, change = ingest(title: "Crystal 1.21.0 is released (updated)")

    change.should eq(ContentIngestor::Change::Updated)
    updated.id.should eq(original.id)
    updated.title.should eq("Crystal 1.21.0 is released (updated)")
    ContentItemQuery.new.select_count.should eq(1)
  end

  # The guarantee that makes re-running ingestion safe: an editor's decision
  # outlives anything the source does afterwards.
  it "never resurrects a rejected item" do
    item, _ = ingest
    ReviewContentItem.update!(item, decision: ContentItem::State::REJECTED, reviewer: "editor")

    refreshed, _ = ingest(title: "Crystal 1.21.0 is released (updated)")

    refreshed.state.should eq(ContentItem::State::REJECTED)
    refreshed.publicly_visible?.should be_false
  end

  it "never retracts an approved item" do
    item, _ = ingest
    ReviewContentItem.update!(item, decision: ContentItem::State::APPROVED, reviewer: "editor")

    refreshed, _ = ingest(title: "Crystal 1.21.0 is released (updated)")

    refreshed.state.should eq(ContentItem::State::APPROVED)
    refreshed.reviewed_by.should eq("editor")
  end

  it "keeps the slug stable across a refresh so published links do not rot" do
    original, _ = ingest
    refreshed, _ = ingest(title: "A completely different headline")

    refreshed.slug.should eq(original.slug)
  end

  it "stores no body for a feed item, so we hold a link rather than the article" do
    item, _ = ingest

    item.body.should be_nil
    item.links_out_only?.should be_true
    item.read_url.should eq(SOURCE)
  end
end
