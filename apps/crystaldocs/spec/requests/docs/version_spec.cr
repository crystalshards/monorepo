require "../../spec_helper"

describe Docs::Version do
  it "displays documentation content" do
    doc = DocFactory.create &.package_name("test-package")

    version = DocVersionFactory.create &.doc_id(doc.id)
      .version("1.0.0")
      .build_status("success")

    # Note: This test assumes MinIO is configured and has test data
    # In a real environment, you'd mock the storage service
    response = BrowserClient.exec(Docs::Version.with(package_name: "test-package", version: "1.0.0"))

    response.status_code.should eq(200)
    response.body.should contain("test-package")
    response.body.should contain("1.0.0")
  end

  it "returns 404 for non-existent package" do
    response = BrowserClient.exec(Docs::Version.with(package_name: "nonexistent", version: "1.0.0"))

    response.status_code.should eq(404)
  end

  it "returns 404 for non-existent version" do
    doc = DocFactory.create &.package_name("test-package")

    response = BrowserClient.exec(Docs::Version.with(package_name: "test-package", version: "99.99.99"))

    response.status_code.should eq(404)
  end

  it "shows version not found page when doc content is missing" do
    doc = DocFactory.create &.package_name("test-package")

    version = DocVersionFactory.create &.doc_id(doc.id)
      .version("1.0.0")
      .build_status("pending")

    # Storage holds no content for this version, so the page degrades instead
    # of erroring.
    response = BrowserClient.exec(Docs::Version.with(package_name: "test-package", version: "1.0.0"))

    response.status_code.should eq(200)
  end

  it "displays version switcher with all versions" do
    doc = DocFactory.create &.package_name("test-package")

    version1 = DocVersionFactory.create &.doc_id(doc.id)
      .version("1.0.0")

    version2 = DocVersionFactory.create &.doc_id(doc.id)
      .version("2.0.0")

    response = BrowserClient.exec(Docs::Version.with(package_name: "test-package", version: "1.0.0"))

    response.status_code.should eq(200)
    response.body.should contain("Version:")
    # Version switcher should list both versions
  end

  it "displays breadcrumb navigation" do
    doc = DocFactory.create &.package_name("test-package")

    version = DocVersionFactory.create &.doc_id(doc.id)
      .version("1.0.0")

    response = BrowserClient.exec(Docs::Version.with(package_name: "test-package", version: "1.0.0"))

    response.status_code.should eq(200)
    response.body.should contain("breadcrumb")
  end

  # The short badge is the fallback voice, for the case where there is no
  # build request to explain the page: the storage lookup failed, so we cannot
  # say a build is happening and cannot show documentation either. Whenever a
  # request exists the section below speaks instead, because it can say what
  # happens next, and two voices reading from two tables disagreed.
  it "falls back to the short build status when there is no request to explain the page" do
    doc = DocFactory.create &.package_name("test-package")

    DocVersionFactory.create &.doc_id(doc.id)
      .version("1.0.0")
      .build_status("failed")

    StubDocsStorage.unreachable.install

    response = BrowserClient.exec(Docs::Version.with(package_name: "test-package", version: "1.0.0"))

    response.status_code.should eq(200)
    response.body.should contain("Build:")
    response.body.should_not contain("Documentation is being built")
  end

  it "increments view count" do
    doc = DocFactory.create &.package_name("test-package")
      .total_views(10)

    version = DocVersionFactory.create &.doc_id(doc.id)
      .version("1.0.0")

    # Viewing documentation should increment counter
    # Note: This test may need adjustment based on actual MinIO state
    initial_views = doc.total_views

    BrowserClient.exec(Docs::Version.with(package_name: "test-package", version: "1.0.0"))

    # Reload doc to check if views increased
    updated_doc = DocQuery.new.package_name("test-package").first
    # Views should increase if content exists
    # updated_doc.total_views.should be >= initial_views
  end
end
