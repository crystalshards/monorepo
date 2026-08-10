require "../../spec_helper"

describe Posts::Show do
  it "shows published post" do
    post = PostFactory.create do |p|
      p.title("Test Post")
      p.content("This is the full content")
      p.published_at(Time.utc - 1.day)
    end

    response = BrowserClient.exec(Posts::Show.with(post.slug))

    response.status.should eq(HTTP::Status.new(200))
    response.body.should contain(post.title)
    response.body.should contain("This is the full content")
  end

  it "increments view count" do
    post = PostFactory.create do |p|
      p.view_count(10)
      p.published_at(Time.utc - 1.day)
    end

    BrowserClient.exec(Posts::Show.with(post.slug))

    # Avram's #reload returns a fresh record rather than mutating in place.
    post.reload.view_count.should eq(11)
  end

  it "increments view count on each visit" do
    post = PostFactory.create do |p|
      p.view_count(5)
      p.published_at(Time.utc - 1.day)
    end

    3.times do
      BrowserClient.exec(Posts::Show.with(post.slug))
    end

    post.reload.view_count.should eq(8)
  end

  it "displays post metadata" do
    post = PostFactory.create do |p|
      p.title("Test Post")
      p.author_name("Jane Doe")
      p.published_at(Time.utc - 1.day)
      p.view_count(100)
    end

    response = BrowserClient.exec(Posts::Show.with(post.slug))

    response.status.should eq(HTTP::Status.new(200))
    response.body.should contain(post.author_name)
    response.body.should contain("100 views")
  end

  it "renders markdown content as HTML" do
    post = PostFactory.create do |p|
      p.content("# Heading\n\nThis is **bold** text.")
      p.published_at(Time.utc - 1.day)
    end

    response = BrowserClient.exec(Posts::Show.with(post.slug))

    response.status.should eq(HTTP::Status.new(200))
    response.body.should contain("<h1>Heading</h1>")
    response.body.should contain("<strong>bold</strong>")
  end

  it "displays tags as links" do
    post = PostFactory.create do |p|
      p.tags(["crystal", "web", "tutorial"])
      p.published_at(Time.utc - 1.day)
    end

    response = BrowserClient.exec(Posts::Show.with(post.slug))

    response.status.should eq(HTTP::Status.new(200))
    response.body.should contain("crystal")
    response.body.should contain("web")
    response.body.should contain("tutorial")
    response.body.should contain("/posts?tag=crystal")
  end

  it "includes newsletter CTA" do
    post = PostFactory.create &.published_at(Time.utc - 1.day)

    response = BrowserClient.exec(Posts::Show.with(post.slug))

    response.status.should eq(HTTP::Status.new(200))
    response.body.should contain("Enjoyed this post")
    response.body.should contain("Subscribe to our newsletter")
  end

  it "returns 404 for unpublished post" do
    # Lucky::ErrorHandler rescues Avram::RecordNotFoundError and renders
    # Errors::Show, so the exception never escapes the HTTP stack. The
    # observable contract is the 404 response.
    post = PostFactory.create &.published_at(nil)

    response = BrowserClient.exec(Posts::Show.with(post.slug))

    response.status_code.should eq(404)
    response.body.should contain("Not found")
  end

  it "returns 404 for non-existent post" do
    response = BrowserClient.exec(Posts::Show.with("non-existent-slug"))

    response.status_code.should eq(404)
    response.body.should contain("Not found")
  end

  it "formats date properly" do
    # Avram reads timestamps back in Time::Location.local, and the page formats
    # them in that zone. Build the date in local time so the rendered day is
    # the one asserted on regardless of the machine's zone.
    post = PostFactory.create do |p|
      p.published_at(Time.local(2025, 3, 15, 12, 0, 0))
    end

    response = BrowserClient.exec(Posts::Show.with(post.slug))

    response.status.should eq(HTTP::Status.new(200))
    response.body.should contain("March 15, 2025")
  end
end
