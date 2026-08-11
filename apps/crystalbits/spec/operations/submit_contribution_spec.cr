require "../spec_helper"

private def valid_params
  {
    title:             "Porting a Sidekiq worker to Crystal",
    body:              "We moved one queue consumer over and the p99 dropped. Here is what broke on the way.",
    original_author:   "Dana Rivera",
    submitter_contact: "dana@example.com",
  }
end

describe SubmitContribution do
  it "stores a submission unpublished" do
    contribution = SubmitContribution.create!(**valid_params)

    contribution.state.should eq(ContentItem::State::SUBMITTED)
    contribution.publicly_visible?.should be_false
    contribution.pending_review?.should be_true
  end

  it "does not appear in the publicly visible query until approved" do
    contribution = SubmitContribution.create!(**valid_params)

    ContentItemQuery.new.publicly_visible.select_count.should eq(0)

    ReviewContentItem.update!(contribution,
      decision: ContentItem::State::APPROVED,
      reviewer: "editor")

    ContentItemQuery.new.publicly_visible.select_count.should eq(1)
  end

  # The permit list is the boundary. If these ever become permitted columns a
  # submitter can publish themselves, so this asserts the boundary directly.
  it "ignores state, origin and machine_drafted supplied as params" do
    params = Avram::Params.new({
      "title"             => "Trying to jump the queue",
      "body"              => valid_params[:body],
      "original_author"   => "Mallory",
      "submitter_contact" => "mallory@example.com",
      "state"             => ContentItem::State::APPROVED,
      "origin"            => ContentItem::Origin::CRYSTAL_BLOG,
      "machine_drafted"   => "true",
      "reviewed_by"       => "not-a-real-editor",
    })

    contribution = SubmitContribution.new(params).tap(&.save).record.not_nil!

    contribution.state.should eq(ContentItem::State::SUBMITTED)
    contribution.origin.should eq(ContentItem::Origin::CONTRIBUTION)
    contribution.machine_drafted.should be_false
    contribution.reviewed_by.should be_nil
  end

  it "records provenance for the submission" do
    contribution = SubmitContribution.create!(**valid_params.merge({canonical_url: "https://dana.example/porting"}))

    contribution.original_author.should eq("Dana Rivera")
    contribution.attribution.should eq("Submitted by Dana Rivera")
    contribution.canonical_url.should eq("https://dana.example/porting")
    contribution.license_note.should eq(SubmitContribution::LICENSE_NOTE)
    contribution.original_published_at.should_not be_nil
  end

  it "keeps the submitted markdown intact and sanitises it at render time" do
    contribution = SubmitContribution.create!(**valid_params.merge({
      body: "Real content here, and enough of it.\n\n<script>alert('xss')</script>\n\nMore real content.",
    }))

    # Stored verbatim so an editor sees exactly what was sent.
    contribution.body.to_s.should contain("<script>")

    # A script on its own line is an HTML block, so it goes entirely.
    rendered = BitsHtml.markdown(contribution.body.to_s)
    rendered.downcase.should_not contain("<script")
    rendered.should_not contain("alert('xss')")
    rendered.should contain("Real content here")
  end

  # Inline HTML inside a paragraph loses its tags but keeps the text between
  # them. That text is inert: it renders as characters in a paragraph. The
  # property that matters is that no tag survives.
  it "renders an inline script as inert text rather than markup" do
    contribution = SubmitContribution.create!(**valid_params.merge({
      body: "Crystal is <script>alert('xss')</script> fast, and this body is long enough.",
    }))

    rendered = BitsHtml.markdown(contribution.body.to_s)

    rendered.downcase.should_not contain("<script")
    rendered.downcase.should_not contain("</script")
    rendered.should contain("Crystal is")
    rendered.should contain("fast")
  end

  it "requires a title, a body, a name and a contact" do
    operation = SubmitContribution.new

    operation.save.should be_false
    operation.title.errors.should_not be_empty
    operation.body.errors.should_not be_empty
    operation.original_author.errors.should_not be_empty
    operation.submitter_contact.errors.should_not be_empty
  end

  it "rejects a malformed email contact" do
    operation = SubmitContribution.new(**valid_params.merge({submitter_contact: "dana@nope"}))

    operation.save.should be_false
    operation.submitter_contact.errors.should_not be_empty
  end

  it "accepts a non-email handle as a contact" do
    contribution = SubmitContribution.create!(**valid_params.merge({submitter_contact: "@dana on the Crystal Discord"}))

    contribution.submitter_contact.should eq("@dana on the Crystal Discord")
  end

  it "rejects a relative canonical link, which would credit us for their work" do
    operation = SubmitContribution.new(**valid_params.merge({canonical_url: "/somewhere"}))

    operation.save.should be_false
    operation.canonical_url.errors.should_not be_empty
  end

  it "leaves source_url null so contributions never collide with ingested items" do
    contribution = SubmitContribution.create!(**valid_params.merge({canonical_url: "https://dana.example/porting"}))

    contribution.source_url.should be_nil
  end

  it "generates a unique slug when two submissions share a title" do
    first = SubmitContribution.create!(**valid_params)
    second = SubmitContribution.create!(**valid_params.merge({submitter_contact: "other@example.com"}))

    first.slug.should_not eq(second.slug)
    second.slug.should start_with(first.slug)
  end
end
