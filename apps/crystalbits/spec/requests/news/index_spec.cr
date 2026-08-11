require "../../spec_helper"

describe News::Index do
  it "renders with nothing approved" do
    response = BrowserClient.exec(News::Index)

    response.status.should eq(HTTP::Status.new(200))
    response.body.should contain("Nothing approved here yet")
  end

  it "shows approved items" do
    item = ContentItemFactory.create &.approved.title("An approved community post")

    response = BrowserClient.exec(News::Index)

    response.body.should contain(item.title)
  end

  # The single most important assertion in this app: the public index is
  # approved-only, whatever produced the row.
  it "hides every pending state, whatever the source" do
    submitted = ContentItemFactory.create do |item|
      item.title("Submitted but unreviewed")
      item.state(ContentItem::State::SUBMITTED)
      item.origin(ContentItem::Origin::CONTRIBUTION)
    end

    ingested = ContentItemFactory.create do |item|
      item.title("Ingested but unreviewed")
      item.state(ContentItem::State::DRAFT)
      item.origin(ContentItem::Origin::CRYSTAL_BLOG)
      item.source_url("https://crystal-lang.org/2026/07/16/1.21.0-released/")
    end

    generated = ContentItemFactory.create do |item|
      item.title("Machine drafted but unreviewed")
      item.state(ContentItem::State::DRAFT)
      item.origin(ContentItem::Origin::GENERATED)
      item.machine_drafted(true)
      item.source_url("https://www.reddit.com/r/crystal_programming/comments/1v9pg4y/")
    end

    rejected = ContentItemFactory.create do |item|
      item.title("Rejected outright")
      item.state(ContentItem::State::REJECTED)
    end

    response = BrowserClient.exec(News::Index)

    response.status.should eq(HTTP::Status.new(200))
    response.body.should_not contain(submitted.title)
    response.body.should_not contain(ingested.title)
    response.body.should_not contain(generated.title)
    response.body.should_not contain(rejected.title)
  end

  it "shows an approved item as soon as it is approved and not before" do
    item = ContentItemFactory.create &.title("Waiting on review")

    BrowserClient.exec(News::Index).body.should_not contain(item.title)

    ReviewContentItem.update!(item, decision: ContentItem::State::APPROVED, reviewer: "editor")

    BrowserClient.exec(News::Index).body.should contain(item.title)
  end

  it "labels a machine-drafted item as machine-drafted" do
    ContentItemFactory.create do |item|
      item.approved
      item.title("Written from community discussion")
      item.origin(ContentItem::Origin::GENERATED)
      item.machine_drafted(true)
      item.attribution("Written by CrystalBits from public community discussion.")
    end

    body = BrowserClient.exec(News::Index).body

    body.should contain("Machine-drafted by CrystalBits")
  end

  it "shows attribution and the source link for a Crystal blog item" do
    ContentItemFactory.create do |item|
      item.approved
      item.title("Crystal 1.21.0 is released!")
      item.origin(ContentItem::Origin::CRYSTAL_BLOG)
      item.body(nil)
      item.source_url("https://crystal-lang.org/2026/07/16/1.21.0-released/")
      item.original_author("Johannes Muller")
      item.attribution("Johannes Muller on the Crystal blog (crystal-lang.org)")
    end

    body = BrowserClient.exec(News::Index).body

    body.should contain("Johannes Muller on the Crystal blog")
    body.should contain("https://crystal-lang.org/2026/07/16/1.21.0-released/")
  end

  it "filters by origin without ever widening past approved" do
    ContentItemFactory.create &.approved.title("Approved contribution").origin(ContentItem::Origin::CONTRIBUTION)

    pending = ContentItemFactory.create do |item|
      item.title("Pending contribution")
      item.origin(ContentItem::Origin::CONTRIBUTION)
    end

    response = BrowserClient.exec(News::Index, origin: ContentItem::Origin::CONTRIBUTION)

    response.body.should contain("Approved contribution")
    response.body.should_not contain(pending.title)
  end

  it "names the real feed on the page" do
    BrowserClient.exec(News::Index).body.should contain("crystal-lang.org/feed.xml")
  end
end
