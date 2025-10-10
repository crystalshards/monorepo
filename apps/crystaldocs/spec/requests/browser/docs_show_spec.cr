require "../../spec_helper"

describe Docs::Show do
  it "redirects to current version when available" do
    doc = DocFactory.create &.package_name("lucky")
      .current_version("1.0.0")

    DocVersionFactory.create &.doc_id(doc.id).version("1.0.0")

    response = ApiClient.exec(Docs::Show.with("lucky"))

    response.status.should eq(302)
    response.headers["Location"].should eq("/docs/lucky/1.0.0")
  end

  it "shows package overview when no current version" do
    doc = DocFactory.create &.package_name("mylib")
      .current_version(nil)
      .description("A Crystal library")

    response = ApiClient.exec(Docs::Show.with("mylib"))

    response.status.should eq(200)
    response.body.should contain("mylib")
    response.body.should contain("A Crystal library")
  end

  it "returns 404 for non-existent package" do
    expect_raises(Lucky::RouteNotFoundError) do
      ApiClient.exec(Docs::Show.with("nonexistent"))
    end
  end

  it "displays package statistics" do
    doc = DocFactory.create &.package_name("popular")
      .total_views(1000)
      .last_updated_at(Time.utc)

    response = ApiClient.exec(Docs::Show.with("popular"))

    response.body.should contain("1000")
    response.body.should contain("views")
  end

  it "lists all available versions" do
    doc = DocFactory.create &.package_name("versioned")

    version1 = DocVersionFactory.create &.doc_id(doc.id)
      .version("1.0.0")
      .published_at(Time.utc - 2.days)
    version2 = DocVersionFactory.create &.doc_id(doc.id)
      .version("2.0.0")
      .published_at(Time.utc)

    response = ApiClient.exec(Docs::Show.with("versioned"))

    response.body.should contain("1.0.0")
    response.body.should contain("2.0.0")
    response.body.should contain("Available Versions")
  end
end
