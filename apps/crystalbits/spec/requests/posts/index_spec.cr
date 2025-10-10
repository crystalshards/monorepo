require "../../spec_helper"

describe Posts::Index do
  it "lists published posts" do
    published_post = PostFactory.create &.published_at(Time.utc - 1.day)
    unpublished_post = PostFactory.create &.published_at(nil)

    response = ApiClient.exec(Posts::Index)

    response.status.should eq(HTTP::Status.new(200))
    response.body.should contain(published_post.title)
    response.body.should_not contain(unpublished_post.title)
  end

  it "shows featured post separately on homepage" do
    featured_post = PostFactory.create &.featured(true).published_at(Time.utc - 1.day)
    regular_post = PostFactory.create &.featured(false).published_at(Time.utc - 2.days)

    response = ApiClient.exec(Home::Index)

    response.status.should eq(HTTP::Status.new(200))
    response.body.should contain("Featured Post")
    response.body.should contain(featured_post.title)
    response.body.should contain(regular_post.title)
  end

  it "paginates posts" do
    # Create 25 posts
    25.times do |i|
      PostFactory.create &.published_at(Time.utc - i.days).title("Post #{i}")
    end

    # First page should show 20 posts
    response = ApiClient.exec(Posts::Index)
    response.status.should eq(HTTP::Status.new(200))
    response.body.should contain("Post 0")
    response.body.should contain("Post 19")
    response.body.should_not contain("Post 24")

    # Second page should show remaining posts
    response = ApiClient.exec(Posts::Index, page: 2)
    response.status.should eq(HTTP::Status.new(200))
    response.body.should contain("Post 20")
    response.body.should contain("Post 24")
    response.body.should_not contain("Post 0")
  end

  it "filters posts by tag" do
    crystal_post = PostFactory.create &.tags(["crystal", "tutorial"]).published_at(Time.utc - 1.day)
    ruby_post = PostFactory.create &.tags(["ruby", "tutorial"]).published_at(Time.utc - 2.days)

    response = ApiClient.exec(Posts::Index, tag: "crystal")

    response.status.should eq(HTTP::Status.new(200))
    response.body.should contain(crystal_post.title)
    response.body.should_not contain(ruby_post.title)
  end

  it "searches posts by title" do
    matching_post = PostFactory.create &.title("Building Web Apps").published_at(Time.utc - 1.day)
    non_matching_post = PostFactory.create &.title("Database Tutorial").published_at(Time.utc - 2.days)

    response = ApiClient.exec(Posts::Index, search: "Web Apps")

    response.status.should eq(HTTP::Status.new(200))
    response.body.should contain(matching_post.title)
    response.body.should_not contain(non_matching_post.title)
  end

  it "searches posts by content" do
    matching_post = PostFactory.create do |post|
      post.title("Crystal Guide")
      post.content("Learn about Crystal web frameworks")
      post.published_at(Time.utc - 1.day)
    end
    non_matching_post = PostFactory.create do |post|
      post.title("Database Guide")
      post.content("Learn about PostgreSQL")
      post.published_at(Time.utc - 2.days)
    end

    response = ApiClient.exec(Posts::Index, search: "web frameworks")

    response.status.should eq(HTTP::Status.new(200))
    response.body.should contain(matching_post.title)
    response.body.should_not contain(non_matching_post.title)
  end

  it "shows recent posts first" do
    older_post = PostFactory.create &.title("Old Post").published_at(Time.utc - 5.days)
    newer_post = PostFactory.create &.title("New Post").published_at(Time.utc - 1.day)

    response = ApiClient.exec(Posts::Index)

    response.status.should eq(HTTP::Status.new(200))
    # Newer post should appear before older post in HTML
    newer_index = response.body.index(newer_post.title).not_nil!
    older_index = response.body.index(older_post.title).not_nil!
    newer_index.should be < older_index
  end

  it "displays post metadata" do
    post = PostFactory.create do |p|
      p.title("Test Post")
      p.author_name("Jane Doe")
      p.published_at(Time.utc - 1.day)
      p.view_count(100)
      p.tags(["crystal", "tutorial"])
    end

    response = ApiClient.exec(Posts::Index)

    response.status.should eq(HTTP::Status.new(200))
    response.body.should contain(post.title)
    response.body.should contain(post.author_name)
    response.body.should contain("100 views")
    response.body.should contain("crystal")
    response.body.should contain("tutorial")
  end

  it "shows excerpt if available" do
    post = PostFactory.create do |p|
      p.excerpt("This is a short excerpt")
      p.published_at(Time.utc - 1.day)
    end

    response = ApiClient.exec(Posts::Index)

    response.status.should eq(HTTP::Status.new(200))
    response.body.should contain("This is a short excerpt")
  end

  it "includes newsletter signup form" do
    PostFactory.create &.published_at(Time.utc - 1.day)

    response = ApiClient.exec(Posts::Index)

    response.status.should eq(HTTP::Status.new(200))
    response.body.should contain("newsletter")
    response.body.should contain("email")
  end
end
