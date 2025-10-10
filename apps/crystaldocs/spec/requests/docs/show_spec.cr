require "../../spec_helper"

describe Docs::Show do
  it "redirects to current version when available" do
    doc = DocFactory.create &.package_name("test-package")
      .current_version("1.0.0")

    version = DocVersionFactory.create &.doc_id(doc.id)
      .version("1.0.0")

    response = ApiClient.exec(Docs::Show, package_name: "test-package")

    response.status.should eq(302)
    response.headers["Location"].should eq("/docs/test-package/1.0.0")
  end

  it "shows package detail when no current version" do
    doc = DocFactory.create &.package_name("test-package")
      .current_version(nil)

    response = ApiClient.exec(Docs::Show, package_name: "test-package")

    response.should send_html(200)
    response.body.should contain("test-package")
  end

  it "returns 404 for non-existent package" do
    expect_raises(Lucky::RouteNotFoundError) do
      ApiClient.exec(Docs::Show, package_name: "nonexistent")
    end
  end

  it "displays available versions list" do
    doc = DocFactory.create &.package_name("test-package")

    version1 = DocVersionFactory.create &.doc_id(doc.id)
      .version("1.0.0")

    version2 = DocVersionFactory.create &.doc_id(doc.id)
      .version("2.0.0")

    response = ApiClient.exec(Docs::Show, package_name: "test-package")

    response.should send_html(200)
    response.body.should contain("Available Versions")
    response.body.should contain("1.0.0")
    response.body.should contain("2.0.0")
  end

  it "displays package statistics" do
    doc = DocFactory.create &.package_name("test-package")
      .total_views(100)

    response = ApiClient.exec(Docs::Show, package_name: "test-package")

    response.should send_html(200)
    response.body.should contain("100")
    response.body.should contain("views")
  end
end
