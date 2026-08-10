require "../../spec_helper"

# The routing and safety contract for serving stored documentation files.
# None of these cases depend on what storage happens to hold.
describe Docs::File do
  get = ->(path : String) {
    BrowserClient.exec(Lucky::RouteHelper.new(:get, path))
  }

  it "sends a deep link written without a version to the current version" do
    doc = DocFactory.create &.package_name("test-package").current_version("1.0.0")
    DocVersionFactory.create &.doc_id(doc.id).version("1.0.0")

    # The shape a reader gets by trimming a URL or copying a link out of a
    # document: no version, just a path.
    response = get.call("/docs/test-package/api/index.html")

    response.status_code.should eq(302)
    response.headers["Location"].should contain("/docs/test-package/1.0.0/api/index.html")
  end

  it "keeps a nested path intact when redirecting" do
    doc = DocFactory.create &.package_name("test-package").current_version("2.1.0")
    DocVersionFactory.create &.doc_id(doc.id).version("2.1.0")

    response = get.call("/docs/test-package/api/models/user.html")

    response.headers["Location"].should contain("/docs/test-package/2.1.0/api/models/user.html")
  end

  it "does not redirect when the package has no current version" do
    DocFactory.create &.package_name("test-package").current_version(nil)

    response = get.call("/docs/test-package/api/index.html")

    response.status_code.should eq(404)
  end

  it "404s a file request for a package that does not exist" do
    response = get.call("/docs/nonexistent/1.0.0/index.html")

    response.status_code.should eq(404)
  end

  it "refuses a path that climbs out of the requested version" do
    doc = DocFactory.create &.package_name("test-package").current_version("1.0.0")
    DocVersionFactory.create &.doc_id(doc.id).version("1.0.0")

    # The path is appended to an object key, so traversal would read another
    # package's documentation.
    response = get.call("/docs/test-package/1.0.0/api/../../../other/1.0.0/index.html")

    response.status_code.should_not eq(200)
  end

  it "refuses a hidden path" do
    doc = DocFactory.create &.package_name("test-package").current_version("1.0.0")
    DocVersionFactory.create &.doc_id(doc.id).version("1.0.0")

    response = get.call("/docs/test-package/1.0.0/.env/x")

    response.status_code.should eq(404)
  end

  it "leaves the version page itself on the version route" do
    doc = DocFactory.create &.package_name("test-package").current_version("1.0.0")
    DocVersionFactory.create &.doc_id(doc.id).version("1.0.0")

    # Adding the file route must not steal /docs/:package/:version, which is
    # our own page rather than a stored file.
    Docs::Version.with(package_name: "test-package", version: "1.0.0").path
      .should eq("/docs/test-package/1.0.0")
  end
end
