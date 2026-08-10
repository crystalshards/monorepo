require "../../../spec_helper"

describe Api::Posts::Create do
  it "creates a new post with valid params" do
    params = {
      post: {
        title:       "Crystal Language Guide",
        slug:        "crystal-language-guide",
        content:     "This is a comprehensive guide to Crystal...",
        author_name: "Crystal Developer",
      },
    }

    response = ApiClient.exec(Api::Posts::Create, **params)

    response.status_code.should eq(201)
    body = JSON.parse(response.body)

    body["title"].should eq("Crystal Language Guide")
    body["slug"].should eq("crystal-language-guide")
    body["author_name"].should eq("Crystal Developer")
  end

  it "returns errors for invalid params" do
    params = {
      post: {
        title: "Crystal Guide",
      },
    }

    response = ApiClient.exec(Api::Posts::Create, **params)

    response.status_code.should eq(422)
    body = JSON.parse(response.body)
    body["errors"].as_a.should_not be_empty
  end

  it "auto-generates slug from title if not provided" do
    params = {
      post: {
        title:       "Crystal Language Guide",
        content:     "This is a comprehensive guide...",
        author_name: "Crystal Developer",
        slug:        "",
      },
    }

    response = ApiClient.exec(Api::Posts::Create, **params)

    response.status_code.should eq(201)
    body = JSON.parse(response.body)
    body["slug"].should eq("crystal-language-guide")
  end

  it "auto-generates excerpt from content if not provided" do
    long_content = "A" * 300

    params = {
      post: {
        title:       "Crystal Guide",
        slug:        "crystal-guide",
        content:     long_content,
        author_name: "Crystal Developer",
      },
    }

    response = ApiClient.exec(Api::Posts::Create, **params)

    response.status_code.should eq(201)
    body = JSON.parse(response.body)
    body["excerpt"].as_s.size.should be <= 203
  end

  it "validates slug uniqueness" do
    PostFactory.create &.slug("crystal-guide")

    params = {
      post: {
        title:       "Another Crystal Guide",
        slug:        "crystal-guide",
        content:     "Different content",
        author_name: "Another Developer",
      },
    }

    response = ApiClient.exec(Api::Posts::Create, **params)

    response.status_code.should eq(422)
  end
end
