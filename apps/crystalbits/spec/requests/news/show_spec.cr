require "../../spec_helper"

describe News::Show do
  it "renders an approved item" do
    item = ContentItemFactory.create do |content|
      content.approved
      content.title("Approved and readable")
      content.body("Some **real** content.")
    end

    response = BrowserClient.exec(News::Show.with(slug: item.slug))

    response.status.should eq(HTTP::Status.new(200))
    response.body.should contain("Approved and readable")
    response.body.should contain("<strong>real</strong>")
  end

  # Knowing the slug is not a way in. The query is scoped to approved rather
  # than filtered after the fact.
  #
  # The canary is generated at runtime rather than written as a literal.
  # Lucky's development error page echoes the source of the spec that made the
  # request, so any string typed here would match itself in the 404 body and
  # the assertion would prove nothing.
  it "404s on a submitted item even when the slug is known" do
    canary = "canary-#{Random::Secure.hex(8)}"

    item = ContentItemFactory.create do |content|
      content.state(ContentItem::State::SUBMITTED)
      content.title("Awaiting review #{canary}")
      content.body("Draft prose #{canary}")
      content.summary("Draft summary #{canary}")
    end

    response = BrowserClient.exec(News::Show.with(slug: item.slug))

    response.status.should eq(HTTP::Status.new(404))
    response.body.should_not contain(canary)
  end

  it "404s on a rejected item" do
    canary = "canary-#{Random::Secure.hex(8)}"

    item = ContentItemFactory.create do |content|
      content.state(ContentItem::State::REJECTED)
      content.title("Turned down #{canary}")
      content.body("Rejected prose #{canary}")
      content.summary("Rejected summary #{canary}")
    end

    response = BrowserClient.exec(News::Show.with(slug: item.slug))

    response.status.should eq(HTTP::Status.new(404))
    response.body.should_not contain(canary)
  end

  it "sanitises a script tag in an approved contribution body" do
    item = ContentItemFactory.create do |content|
      content.approved
      content.body("Real prose here.\n\n<script>alert('xss')</script>\n\nMore real prose.")
    end

    response = BrowserClient.exec(News::Show.with(slug: item.slug))

    response.status.should eq(HTTP::Status.new(200))
    response.body.downcase.should_not contain("<script")
    response.body.should_not contain("alert('xss')")
    response.body.should contain("Real prose here")
  end

  it "puts the machine-drafted notice above a generated body" do
    item = ContentItemFactory.create do |content|
      content.approved
      content.origin(ContentItem::Origin::GENERATED)
      content.machine_drafted(true)
      content.body("Our own words about a discussion.")
      content.source_urls([
        "https://www.reddit.com/r/crystal_programming/comments/1v9pg4y/",
        "https://www.reddit.com/r/crystal_programming/comments/1vf7576/",
      ])
    end

    body = BrowserClient.exec(News::Show.with(slug: item.slug)).body

    body.should contain("Machine-drafted")
    body.index("Machine-drafted").not_nil!.should be < body.index("Our own words about a discussion").not_nil!
    body.should contain("comments/1v9pg4y")
    body.should contain("comments/1vf7576")
  end

  it "sends a feed item out to its source rather than restating it here" do
    item = ContentItemFactory.create do |content|
      content.approved
      content.origin(ContentItem::Origin::CRYSTAL_BLOG)
      content.body(nil)
      content.source_url("https://crystal-lang.org/2026/07/16/1.21.0-released/")
    end

    response = BrowserClient.exec(News::Show.with(slug: item.slug))

    response.status.should eq(HTTP::Status.new(302))
    response.headers["Location"].should eq("https://crystal-lang.org/2026/07/16/1.21.0-released/")
  end
end
