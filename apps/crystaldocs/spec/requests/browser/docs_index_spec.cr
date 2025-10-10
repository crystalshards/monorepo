require "../../spec_helper"

describe Docs::Index do
  it "renders docs index page" do
    response = ApiClient.exec(Docs::Index)

    response.status.should eq(200)
    response.body.should contain("Browse Documentation")
  end

  it "lists all documentation packages" do
    doc1 = DocFactory.create &.package_name("crystal-db")
    doc2 = DocFactory.create &.package_name("lucky")

    DocVersionFactory.create &.doc_id(doc1.id)
    DocVersionFactory.create &.doc_id(doc2.id)

    response = ApiClient.exec(Docs::Index)

    response.body.should contain("crystal-db")
    response.body.should contain("lucky")
  end

  it "searches packages by name" do
    http_doc = DocFactory.create &.package_name("http-client")
    db_doc = DocFactory.create &.package_name("crystal-db")

    DocVersionFactory.create &.doc_id(http_doc.id)
    DocVersionFactory.create &.doc_id(db_doc.id)

    response = ApiClient.exec(Docs::Index, query: "http")

    response.body.should contain("http-client")
    response.body.should_not contain("crystal-db")
    response.body.should contain("Search: http")
  end

  it "searches packages by description" do
    doc = DocFactory.create &.package_name("mylib")
      .description("HTTP client for Crystal")

    DocVersionFactory.create &.doc_id(doc.id)

    response = ApiClient.exec(Docs::Index, query: "HTTP")

    response.body.should contain("mylib")
    response.body.should contain("HTTP client for Crystal")
  end

  it "shows search results count" do
    3.times do |i|
      doc = DocFactory.create &.package_name("lib-#{i}")
      DocVersionFactory.create &.doc_id(doc.id)
    end

    response = ApiClient.exec(Docs::Index)

    response.body.should contain("3 packages")
  end

  it "paginates results" do
    25.times do |i|
      doc = DocFactory.create &.package_name("package-#{i}")
      DocVersionFactory.create &.doc_id(doc.id)
    end

    response = ApiClient.exec(Docs::Index, page: 1)
    response.body.should contain("Page 1")
    response.body.should contain("Next")

    response = ApiClient.exec(Docs::Index, page: 2)
    response.body.should contain("Page 2")
    response.body.should contain("Previous")
  end

  it "shows empty state when no packages" do
    response = ApiClient.exec(Docs::Index)

    response.body.should contain("No documentation available")
  end

  it "shows empty state for search with no results" do
    response = ApiClient.exec(Docs::Index, query: "nonexistent")

    response.body.should contain("No packages found matching")
    response.body.should contain("nonexistent")
  end
end
