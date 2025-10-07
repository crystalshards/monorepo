require "../../../spec_helper"

describe Api::Posts::Index do
  it "returns a list of published posts" do
    post1 = PostFactory.create &.title("Crystal Guide")
    post2 = PostFactory.create &.title("Lucky Framework Tutorial")
    PostFactory.create &.published_at(nil)

    response = ApiClient.exec(Api::Posts::Index)

    response.status_code.should eq(200)
    body = JSON.parse(response.body)

    body["posts"].as_a.size.should eq(2)
    body["total"].should eq(2)
  end

  it "filters by tag" do
    PostFactory.create &.tags(["crystal", "tutorial"])
    PostFactory.create &.tags(["web", "api"])

    response = ApiClient.exec(Api::Posts::Index, tag: "crystal")

    body = JSON.parse(response.body)
    body["posts"].as_a.size.should eq(1)
  end

  it "searches by title or content" do
    PostFactory.create &.title("Crystal Language Guide")
    PostFactory.create &.content("This post is about Crystal programming")
    PostFactory.create &.title("Ruby Tutorial").content("This is about Ruby programming language")

    response = ApiClient.exec(Api::Posts::Index, q: "Crystal")

    body = JSON.parse(response.body)
    body["posts"].as_a.size.should eq(2)
  end

  it "filters featured posts" do
    PostFactory.create &.featured(true)
    PostFactory.create &.featured(false)

    response = ApiClient.exec(Api::Posts::Index, featured: "true")

    body = JSON.parse(response.body)
    body["posts"].as_a.size.should eq(1)
    body["posts"][0]["featured"].should eq(true)
  end

  it "paginates results" do
    25.times { PostFactory.create }

    response = ApiClient.exec(Api::Posts::Index, page: "2", per_page: "10")

    body = JSON.parse(response.body)
    body["posts"].as_a.size.should eq(10)
    body["page"].should eq(2)
    body["per_page"].should eq(10)
    body["total"].should eq(25)
  end

  it "sorts by popular when requested" do
    PostFactory.create &.view_count(100)
    PostFactory.create &.view_count(500)
    PostFactory.create &.view_count(50)

    response = ApiClient.exec(Api::Posts::Index, popular: "true")

    body = JSON.parse(response.body)
    body["posts"][0]["view_count"].should eq(500)
    body["posts"][1]["view_count"].should eq(100)
    body["posts"][2]["view_count"].should eq(50)
  end
end
