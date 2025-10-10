require "../../spec_helper"

describe Home::Index do
  it "shows the homepage with stats" do
    doc1 = DocFactory.create &.package_name("http-client")
      .description("HTTP client library")
      .total_views(100)

    doc2 = DocFactory.create &.package_name("database")
      .description("Database ORM")
      .total_views(50)

    response = ApiClient.exec(Home::Index)

    response.status.should eq(200)
    response.body.should contain("CrystalDocs")
    response.body.should contain("Crystal Shard Documentation")
  end

  it "displays package and version counts" do
    DocFactory.create_pair

    DocVersionFactory.create &.doc_id(DocQuery.new.first.id)
    DocVersionFactory.create &.doc_id(DocQuery.new.last.id)

    response = ApiClient.exec(Home::Index)

    response.status.should eq(200)
    response.body.should contain("2")
    response.body.should contain("Packages")
    response.body.should contain("Versions")
  end

  it "shows recently updated documentation" do
    recent_doc = DocFactory.create &.package_name("recent-shard")
      .last_updated_at(Time.utc - 1.hour)

    old_doc = DocFactory.create &.package_name("old-shard")
      .last_updated_at(Time.utc - 30.days)

    response = ApiClient.exec(Home::Index)

    response.status.should eq(200)
    response.body.should contain("Recently Updated")
  end

  it "shows popular documentation" do
    popular_doc = DocFactory.create &.package_name("popular-shard")
      .total_views(1000)

    unpopular_doc = DocFactory.create &.package_name("unpopular-shard")
      .total_views(10)

    response = ApiClient.exec(Home::Index)

    response.status.should eq(200)
    response.body.should contain("Popular Packages")
  end

  it "handles empty state gracefully" do
    response = ApiClient.exec(Home::Index)

    response.status.should eq(200)
    response.body.should contain("No documentation available yet")
  end
end
