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

    post.reload
    post.view_count.should eq(11)
  end

  it "increments view count on each visit" do
    post = PostFactory.create do |p|
      p.view_count(5)
      p.published_at(Time.utc - 1.day)
    end

    3.times do
      BrowserClient.exec(Posts::Show.with(post.slug))
    end

    post.reload
    post.view_count.should eq(8)
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
    post = PostFactory.create &.published_at(nil)

    expect_raises(Avram::RecordNotFoundError) do
      BrowserClient.exec(Posts::Show.with(post.slug))
    end
  end

  it "returns 404 for non-existent post" do
    expect_raises(Avram::RecordNotFoundError) do
      BrowserClient.exec(Posts::Show.with("non-existent-slug"))
    end
  end

  it "formats date properly" do
    post = PostFactory.create do |p|
      p.published_at(Time.utc(2025, 3, 15))
    end

    response = BrowserClient.exec(Posts::Show.with(post.slug))

    response.status.should eq(HTTP::Status.new(200))
    response.body.should contain("March 15, 2025")
  end
end
