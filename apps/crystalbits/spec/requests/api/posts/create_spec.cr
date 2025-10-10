require "../../../spec_helper"

describe Api::Posts::Create do
  pending "creates a new post with valid params" do
    # TODO: Fix ApiClient/BrowserClient to send form-encoded data instead of JSON
    # See issue #49 for investigation details
    params = {
      post: {
        title:       "Crystal Language Guide",
        slug:        "crystal-language-guide",
        content:     "This is a comprehensive guide to Crystal...",
        author_name: "Crystal Developer",
      },
    }

    response = ApiClient.exec(Api::Posts::Create, **params)

    if response.status_code != 201
      pp! response.status_code, response.body
    end
    response.status_code.should eq(201)
    body = JSON.parse(response.body)

    body["title"].should eq("Crystal Language Guide")
    body["slug"].should eq("crystal-language-guide")
    body["author_name"].should eq("Crystal Developer")
  end

  pending "returns errors for invalid params" do
    # TODO: Fix ApiClient/BrowserClient to send form-encoded data instead of JSON
    # See issue #49 for investigation details
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

  pending "auto-generates slug from title if not provided" do
    # TODO: Fix ApiClient/BrowserClient to send form-encoded data instead of JSON
    # See issue #49 for investigation details
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

  pending "auto-generates excerpt from content if not provided" do
    # TODO: Fix ApiClient/BrowserClient to send form-encoded data instead of JSON
    # See issue #49 for investigation details
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

  pending "validates slug uniqueness" do
    # TODO: Fix ApiClient/BrowserClient to send form-encoded data instead of JSON
    # See issue #49 for investigation details
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
