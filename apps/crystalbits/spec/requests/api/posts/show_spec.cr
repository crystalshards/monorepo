require "../../../spec_helper"

describe Api::Posts::Show do
  it "returns a post by slug" do
    post = PostFactory.create &.slug("crystal-guide")

    response = ApiClient.exec(Api::Posts::Show, slug: "crystal-guide")

    response.status_code.should eq(200)
    body = JSON.parse(response.body)

    body["id"].should eq(post.id)
    body["slug"].should eq("crystal-guide")
  end

  it "increments view count" do
    post = PostFactory.create &.view_count(10)

    response = ApiClient.exec(Api::Posts::Show, slug: post.slug)

    body = JSON.parse(response.body)
    body["view_count"].should eq(11)

    reloaded_post = PostQuery.find(post.id)
    reloaded_post.view_count.should eq(11)
  end

  it "returns 404 for non-existent post" do
    response = ApiClient.exec(Api::Posts::Show, slug: "non-existent")

    response.status_code.should eq(404)
    body = JSON.parse(response.body)
    body["error"].should eq("Post not found")
  end
end
