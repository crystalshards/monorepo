require "../../spec_helper"

# What the page says about the build, next to what it is actually showing.
#
# This is the pair that made the site look dead. `doc_versions.build_status` is
# set to "pending" when a version is registered and, until the builder was
# taught to write it, was never set again by anything: not on success, not on
# failure. Every version said pending forever.
#
# The page then printed that badge unconditionally, above the documentation it
# had just loaded. So a page could render a README and an API section under the
# words "Build: pending", which reads as "nothing has been built" to anyone
# looking, and is what "still no docs" described.
describe "what the page says about the build" do
  planted = ->(status : String) {
    doc = DocFactory.create &.package_name("badge-pkg").current_version("1.0.0")
    DocVersionFactory.create &.doc_id(doc.id).version("1.0.0").build_status(status)
    doc
  }

  get = -> { BrowserClient.exec(Lucky::RouteHelper.new(:get, "/docs/badge-pkg/1.0.0")) }

  it "says nothing about the build when it is showing the documentation" do
    # Deliberately the stale value, because that is the row real packages
    # carried while their documentation was published and rendering.
    planted.call("pending")
    StubDocsStorage.holding.install
    RecordingBuildQueue.install

    response = get.call

    response.status_code.should eq(200)
    response.body.should contain("A planted document")
    response.body.should_not contain("Build:")
  end

  # The badge still earns its place when there is nothing to show: it is the
  # explanation for a thin page.
  it "still explains a page that has no documentation on it" do
    planted.call("pending")
    StubDocsStorage.empty.install
    RecordingBuildQueue.install

    response = get.call

    response.status_code.should eq(200)
    response.body.should contain("Documentation is being built")
  end

  it "does not claim a build is happening when the store could not be reached" do
    planted.call("success")
    StubDocsStorage.unreachable.install
    RecordingBuildQueue.install

    response = get.call

    response.status_code.should eq(200)
    response.body.should_not contain("Documentation is being built")
  end
end
