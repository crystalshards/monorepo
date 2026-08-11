require "../../spec_helper"

describe Contribute::Show do
  it "explains what is wanted and what happens next" do
    response = BrowserClient.exec(Contribute::Show)

    response.status.should eq(HTTP::Status.new(200))
    response.body.should contain("What we are after")
    response.body.should contain("What happens next")
    response.body.should contain("Nothing here is published automatically")
  end

  it "offers a form with every field the operation needs" do
    body = BrowserClient.exec(Contribute::Show).body

    body.should contain(%(name="content_item:title"))
    body.should contain(%(name="content_item:body"))
    body.should contain(%(name="content_item:original_author"))
    body.should contain(%(name="content_item:submitter_contact"))
    body.should contain(%(name="content_item:canonical_url"))
    body.should contain("_csrf")
  end
end

describe Contributions::Create do
  it "stores a submission unpublished and redirects" do
    response = BrowserClient.exec(Contributions::Create, content_item: {
      title:             "What I learned porting a worker to Crystal",
      body:              "A real body with enough words in it to clear the minimum length check.",
      original_author:   "Dana Rivera",
      submitter_contact: "dana@example.com",
    })

    response.status.should eq(HTTP::Status.new(302))
    response.headers["Location"].should contain("/contributions/thanks")

    contribution = ContentItemQuery.new.first
    contribution.title.should eq("What I learned porting a worker to Crystal")
    contribution.state.should eq(ContentItem::State::SUBMITTED)
    contribution.publicly_visible?.should be_false
  end

  it "does not put the submission on the public index" do
    BrowserClient.exec(Contributions::Create, content_item: {
      title:             "Straight to the front page please",
      body:              "A real body with enough words in it to clear the minimum length check.",
      original_author:   "Mallory",
      submitter_contact: "mallory@example.com",
    })

    response = BrowserClient.exec(News::Index)

    response.status.should eq(HTTP::Status.new(200))
    response.body.should_not contain("Straight to the front page please")
  end

  it "re-renders the form with errors instead of storing an invalid submission" do
    response = BrowserClient.exec(Contributions::Create, content_item: {
      title:             "",
      body:              "too short",
      original_author:   "",
      submitter_contact: "",
    })

    response.status.should eq(HTTP::Status.new(200))
    response.body.should contain("form-error")
    ContentItemQuery.new.select_count.should eq(0)
  end

  it "stores hostile markdown without executing it anywhere it is shown" do
    BrowserClient.exec(Contributions::Create, content_item: {
      title:             "Innocent looking title",
      body:              "Real content that is long enough to pass validation.\n\n<script>alert('xss')</script>",
      original_author:   "Mallory",
      submitter_contact: "mallory@example.com",
    })

    contribution = ContentItemQuery.new.first
    ReviewContentItem.update!(contribution, decision: ContentItem::State::APPROVED, reviewer: "editor")

    response = BrowserClient.exec(News::Show.with(slug: contribution.slug))

    response.status.should eq(HTTP::Status.new(200))
    response.body.downcase.should_not contain("<script")
    response.body.should_not contain("alert('xss')")
  end

  it "never publishes the submitter's contact" do
    BrowserClient.exec(Contributions::Create, content_item: {
      title:             "A perfectly good post",
      body:              "Real content that is long enough to pass validation, with something to say.",
      original_author:   "Dana Rivera",
      submitter_contact: "dana-private@example.com",
    })

    contribution = ContentItemQuery.new.first
    ReviewContentItem.update!(contribution, decision: ContentItem::State::APPROVED, reviewer: "editor")

    BrowserClient.exec(News::Index).body.should_not contain("dana-private@example.com")
    BrowserClient.exec(News::Show.with(slug: contribution.slug)).body
      .should_not contain("dana-private@example.com")
  end
end

describe Contributions::Thanks do
  it "tells the contributor the submission is not public yet" do
    response = BrowserClient.exec(Contributions::Thanks)

    response.status.should eq(HTTP::Status.new(200))
    response.body.should contain("it is not public")
  end
end
