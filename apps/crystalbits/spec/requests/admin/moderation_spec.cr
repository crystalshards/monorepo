require "../../spec_helper"

private def as_editor(user = "editor", password = "letmein", &)
  EditorCredentials.configure do |settings|
    settings.username = user
    settings.password = password
  end

  yield "Basic #{Base64.strict_encode("#{user}:#{password}")}"
ensure
  EditorCredentials.configure do |settings|
    settings.username = nil
    settings.password = nil
  end
end

private def get_moderation(auth : String?)
  client = BrowserClient.new
  client.headers(Authorization: auth) if auth
  client.exec(Admin::Moderation::Index)
end

describe Admin::Moderation::Index do
  it "fails closed when no editor credentials are configured" do
    EditorCredentials.configure do |settings|
      settings.username = nil
      settings.password = nil
    end

    response = get_moderation(nil)

    response.status.should eq(HTTP::Status.new(503))
    response.body.should contain("BITS_EDITOR_USER")
  end

  it "refuses an unauthenticated request when credentials are configured" do
    as_editor do |_auth|
      response = get_moderation(nil)

      response.status.should eq(HTTP::Status.new(401))
      response.headers["WWW-Authenticate"].should contain("Basic")
    end
  end

  it "refuses a wrong password" do
    as_editor do |_auth|
      wrong = "Basic #{Base64.strict_encode("editor:nope")}"

      get_moderation(wrong).status.should eq(HTTP::Status.new(401))
    end
  end

  it "shows the pending queue to an authenticated editor" do
    pending = ContentItemFactory.create &.title("Waiting for review")

    as_editor do |auth|
      response = get_moderation(auth)

      response.status.should eq(HTTP::Status.new(200))
      response.body.should contain(pending.title)
    end
  end

  it "renders a submitted body through the sanitiser, not raw" do
    ContentItemFactory.create do |item|
      item.title("Hostile submission")
      item.state(ContentItem::State::SUBMITTED)
      item.body("Looks fine.\n\n<script>alert('pwn the editor')</script>")
    end

    as_editor do |auth|
      body = get_moderation(auth).body

      # The page ships its own first-party script tag (the announcement bar's
      # dismiss control), so the tripwire is the submitted tag itself rather
      # than the string "<script" anywhere on the page.
      body.downcase.should_not contain("<script>alert")
      body.should_not contain("alert('pwn the editor')")
    end
  end

  it "says machine drafting is off when no model is configured" do
    DraftGenerator.configure do |settings|
      settings.api_key = nil
      settings.model = nil
    end

    as_editor do |auth|
      body = get_moderation(auth).body

      body.should contain("Machine drafting is off")
      body.should contain("BITS_MODEL_API_KEY")
    end
  end
end

describe ReviewContentItem do
  it "is the only thing that makes an item public" do
    item = ContentItemFactory.create

    item.publicly_visible?.should be_false

    ReviewContentItem.update!(item, decision: ContentItem::State::APPROVED, reviewer: "dana")

    item.reload.publicly_visible?.should be_true
  end

  it "records who decided and when" do
    item = ContentItemFactory.create

    reviewed = ReviewContentItem.update!(item, decision: ContentItem::State::APPROVED, reviewer: "dana")

    reviewed.reviewed_by.should eq("dana")
    reviewed.reviewed_at.should_not be_nil
  end

  it "refuses a decision that is not approve or reject" do
    item = ContentItemFactory.create

    operation = ReviewContentItem.new(item, decision: "published", reviewer: "dana")

    operation.save.should be_false
    operation.decision.errors.should_not be_empty
    item.reload.state.should eq(ContentItem::State::DRAFT)
  end

  it "refuses a decision with no reviewer" do
    item = ContentItemFactory.create

    operation = ReviewContentItem.new(item, decision: ContentItem::State::APPROVED, reviewer: "")

    operation.save.should be_false
    item.reload.publicly_visible?.should be_false
  end

  it "lets an editor retract something already approved" do
    item = ContentItemFactory.create &.approved

    ReviewContentItem.update!(item, decision: ContentItem::State::REJECTED, reviewer: "dana")

    item.reload.publicly_visible?.should be_false
  end
end

describe EditorCredentials do
  it "reports itself unconfigured when either half is missing" do
    EditorCredentials.configure do |settings|
      settings.username = "editor"
      settings.password = nil
    end

    EditorCredentials.configured?.should be_false
  end

  it "never verifies anything while unconfigured" do
    EditorCredentials.configure do |settings|
      settings.username = nil
      settings.password = nil
    end

    EditorCredentials.verify("", "").should be_false
    EditorCredentials.verify("editor", "letmein").should be_false
  end

  it "parses a Basic header and rejects anything else" do
    EditorCredentials.from_basic_auth("Basic #{Base64.strict_encode("a:b")}").should eq({"a", "b"})
    EditorCredentials.from_basic_auth("Bearer token").should be_nil
    EditorCredentials.from_basic_auth("Basic not-base64!!").should be_nil
    EditorCredentials.from_basic_auth(nil).should be_nil
  end
end
