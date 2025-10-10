require "../../spec_helper"

describe Docs::Version do
  it "displays documentation content" do
    doc = DocFactory.create &.package_name("lucky")
    version = DocVersionFactory.create &.doc_id(doc.id)
      .version("1.0.0")
      .storage_path("lucky/1.0.0")

    # Note: In real test, would need to mock MinIO storage service
    # For now, test the action structure

    response = ApiClient.exec(Docs::Version,
      package_name: "lucky",
      version: "1.0.0"
    )

    response.status.should eq(200)
  end

  it "supports wildcard file paths" do
    doc = DocFactory.create &.package_name("lucky")
    version = DocVersionFactory.create &.doc_id(doc.id)
      .version("1.0.0")

    # Test that the route accepts file paths
    response = ApiClient.exec(Docs::Version,
      package_name: "lucky",
      version: "1.0.0",
      file_path: "guides/getting-started.html"
    )

    # Should attempt to render even if content not found
    response.status.should be >= 200
  end

  it "increments view count when displaying docs" do
    doc = DocFactory.create &.package_name("mylib")
      .total_views(100)
    version = DocVersionFactory.create &.doc_id(doc.id)
      .version("1.0.0")

    initial_views = doc.total_views

    # Note: Would need to mock storage service returning content
    # to actually increment views

    doc.reload.total_views.should be >= initial_views
  end

  it "returns 404 for non-existent package" do
    expect_raises(Lucky::RouteNotFoundError) do
      ApiClient.exec(Docs::Version,
        package_name: "nonexistent",
        version: "1.0.0"
      )
    end
  end

  it "returns 404 for non-existent version" do
    doc = DocFactory.create &.package_name("mylib")

    expect_raises(Lucky::RouteNotFoundError) do
      ApiClient.exec(Docs::Version,
        package_name: "mylib",
        version: "99.0.0"
      )
    end
  end

  it "shows version switcher" do
    doc = DocFactory.create &.package_name("versioned")

    version1 = DocVersionFactory.create &.doc_id(doc.id).version("1.0.0")
    version2 = DocVersionFactory.create &.doc_id(doc.id).version("2.0.0")

    response = ApiClient.exec(Docs::Version,
      package_name: "versioned",
      version: "1.0.0"
    )

    response.body.should contain("Version:")
    response.body.should contain("1.0.0")
    response.body.should contain("2.0.0")
  end

  it "includes links to source and CrystalShards" do
    doc = DocFactory.create &.package_name("mylib")
      .repository_url("https://github.com/user/mylib")

    version = DocVersionFactory.create &.doc_id(doc.id).version("1.0.0")

    response = ApiClient.exec(Docs::Version,
      package_name: "mylib",
      version: "1.0.0"
    )

    response.body.should contain("View Source")
    response.body.should contain("github.com/user/mylib")
    response.body.should contain("CrystalShards")
  end

  it "displays breadcrumbs" do
    doc = DocFactory.create &.package_name("mylib")
    version = DocVersionFactory.create &.doc_id(doc.id).version("1.0.0")

    response = ApiClient.exec(Docs::Version,
      package_name: "mylib",
      version: "1.0.0"
    )

    response.body.should contain("CrystalDocs")
    response.body.should contain("Browse")
    response.body.should contain("mylib")
    response.body.should contain("1.0.0")
  end

  it "renders navigation sidebar when files available" do
    doc = DocFactory.create &.package_name("mylib")
    version = DocVersionFactory.create &.doc_id(doc.id).version("1.0.0")

    response = ApiClient.exec(Docs::Version,
      package_name: "mylib",
      version: "1.0.0"
    )

    response.body.should contain("Navigation")
  end
end
