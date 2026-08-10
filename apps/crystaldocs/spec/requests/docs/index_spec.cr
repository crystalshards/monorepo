require "../../spec_helper"

describe Docs::Index do
  it "lists all documentation packages" do
    doc1 = DocFactory.create &.package_name("http-client")
    doc2 = DocFactory.create &.package_name("database")

    response = BrowserClient.exec(Docs::Index)

    response.status_code.should eq(200)
    response.body.should contain("http-client")
    response.body.should contain("database")
  end

  it "searches documentation by package name" do
    http_doc = DocFactory.create &.package_name("http-client")
    db_doc = DocFactory.create &.package_name("database")

    response = BrowserClient.exec(Docs::Index.with(query: "http"))

    response.status_code.should eq(200)
    response.body.should contain("http-client")
    response.body.should_not contain("database")
  end

  it "searches documentation by description" do
    http_doc = DocFactory.create &.package_name("client")
      .description("HTTP client library for Crystal")

    # The excluded package needs a name that cannot occur in the page's own
    # markup: "orm" is a substring of the search bar's <form class="search-form">,
    # so asserting on it tested the layout rather than the query.
    db_doc = DocFactory.create &.package_name("postgres-driver")
      .description("Database abstraction layer")

    response = BrowserClient.exec(Docs::Index.with(query: "HTTP"))

    response.status_code.should eq(200)
    response.body.should contain("client")
    response.body.should_not contain("postgres-driver")
  end

  it "shows search results count" do
    DocFactory.create &.package_name("test-package")

    response = BrowserClient.exec(Docs::Index.with(query: "test"))

    response.status_code.should eq(200)
    response.body.should contain("Found 1 package")
  end

  it "paginates results" do
    25.times do |i|
      DocFactory.create &.package_name("package-#{i}")
    end

    response = BrowserClient.exec(Docs::Index.with(page: 1))

    response.status_code.should eq(200)
    response.body.should contain("Page 1")

    response_page2 = BrowserClient.exec(Docs::Index.with(page: 2))
    response_page2.status_code.should eq(200)
    response_page2.body.should contain("Page 2")
  end

  it "handles empty search results" do
    DocFactory.create &.package_name("existing-package")

    response = BrowserClient.exec(Docs::Index.with(query: "nonexistent"))

    response.status_code.should eq(200)
    response.body.should contain("No packages found")
  end

  it "shows empty state when no documentation exists" do
    response = BrowserClient.exec(Docs::Index)

    response.status_code.should eq(200)
    response.body.should contain("No documentation available yet")
  end

  it "orders results by last updated date" do
    old_doc = DocFactory.create &.package_name("old-package")
      .last_updated_at(Time.utc - 30.days)

    new_doc = DocFactory.create &.package_name("new-package")
      .last_updated_at(Time.utc - 1.hour)

    response = BrowserClient.exec(Docs::Index)

    response.status_code.should eq(200)
    # New package should appear before old package in HTML
    new_pos = response.body.index("new-package")
    old_pos = response.body.index("old-package")

    if new_pos && old_pos
      new_pos.should be < old_pos
    end
  end
end
