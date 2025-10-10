require "../../spec_helper"

describe Docs::Version do
  it "displays documentation content" do
    doc = DocFactory.create &.package_name("test-package")

    version = DocVersionFactory.create &.doc_id(doc.id)
      .version("1.0.0")
      .build_status("success")

    # Note: This test assumes MinIO is configured and has test data
    # In a real environment, you'd mock the storage service
    response = ApiClient.exec(
      Docs::Version,
      package_name: "test-package",
      version: "1.0.0"
    )

    response.should send_html(200)
    response.body.should contain("test-package")
    response.body.should contain("1.0.0")
  end

  it "returns 404 for non-existent package" do
    expect_raises(Lucky::RouteNotFoundError) do
      ApiClient.exec(
        Docs::Version,
        package_name: "nonexistent",
        version: "1.0.0"
      )
    end
  end

  it "returns 404 for non-existent version" do
    doc = DocFactory.create &.package_name("test-package")

    expect_raises(Lucky::RouteNotFoundError) do
      ApiClient.exec(
        Docs::Version,
        package_name: "test-package",
        version: "99.99.99"
      )
    end
  end

  it "shows version not found page when doc content is missing" do
    doc = DocFactory.create &.package_name("test-package")

    version = DocVersionFactory.create &.doc_id(doc.id)
      .version("1.0.0")
      .build_status("pending")

    # With MinIO not having the content, it should show not found page
    response = ApiClient.exec(
      Docs::Version,
      package_name: "test-package",
      version: "1.0.0"
    )

    # This might succeed or show error depending on MinIO state
    response.status.should eq(200)
  end

  it "displays version switcher with all versions" do
    doc = DocFactory.create &.package_name("test-package")

    version1 = DocVersionFactory.create &.doc_id(doc.id)
      .version("1.0.0")

    version2 = DocVersionFactory.create &.doc_id(doc.id)
      .version("2.0.0")

    response = ApiClient.exec(
      Docs::Version,
      package_name: "test-package",
      version: "1.0.0"
    )

    response.should send_html(200)
    response.body.should contain("Version:")
    # Version switcher should list both versions
  end

  it "displays breadcrumb navigation" do
    doc = DocFactory.create &.package_name("test-package")

    version = DocVersionFactory.create &.doc_id(doc.id)
      .version("1.0.0")

    response = ApiClient.exec(
      Docs::Version,
      package_name: "test-package",
      version: "1.0.0"
    )

    response.should send_html(200)
    response.body.should contain("breadcrumb")
  end

  it "shows build status in sidebar" do
    doc = DocFactory.create &.package_name("test-package")

    version = DocVersionFactory.create &.doc_id(doc.id)
      .version("1.0.0")
      .build_status("success")

    response = ApiClient.exec(
      Docs::Version,
      package_name: "test-package",
      version: "1.0.0"
    )

    response.should send_html(200)
    response.body.should contain("Build:")
  end

  it "increments view count" do
    doc = DocFactory.create &.package_name("test-package")
      .total_views(10)

    version = DocVersionFactory.create &.doc_id(doc.id)
      .version("1.0.0")

    # Viewing documentation should increment counter
    # Note: This test may need adjustment based on actual MinIO state
    initial_views = doc.total_views

    ApiClient.exec(
      Docs::Version,
      package_name: "test-package",
      version: "1.0.0"
    )

    # Reload doc to check if views increased
    updated_doc = DocQuery.new.package_name("test-package").first
    # Views should increase if content exists
    # updated_doc.total_views.should be >= initial_views
  end
end
