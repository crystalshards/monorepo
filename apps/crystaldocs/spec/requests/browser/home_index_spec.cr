require "../../spec_helper"

describe Home::Index do
  it "renders homepage successfully" do
    response = ApiClient.exec(Home::Index)

    response.status.should eq(200)
    response.body.should contain("CrystalDocs")
    response.body.should contain("Crystal Shard Documentation")
  end

  it "displays total package and version counts" do
    # Create test data
    doc1 = DocFactory.create
    doc2 = DocFactory.create
    DocVersionFactory.create &.doc_id(doc1.id)
    DocVersionFactory.create &.doc_id(doc2.id)

    response = ApiClient.exec(Home::Index)

    response.body.should contain("2") # 2 packages
    response.body.should contain("Packages")
    response.body.should contain("Versions")
  end

  it "shows recently updated docs" do
    recent_doc = DocFactory.create &.package_name("recent-shard")
      .last_updated_at(Time.utc)
    old_doc = DocFactory.create &.package_name("old-shard")
      .last_updated_at(Time.utc - 30.days)

    DocVersionFactory.create &.doc_id(recent_doc.id)
    DocVersionFactory.create &.doc_id(old_doc.id)

    response = ApiClient.exec(Home::Index)

    response.body.should contain("recent-shard")
    response.body.should contain("Recently Updated")
  end

  it "shows popular docs" do
    popular_doc = DocFactory.create &.package_name("popular-shard")
      .total_views(1000)
    unpopular_doc = DocFactory.create &.package_name("unpopular-shard")
      .total_views(10)

    DocVersionFactory.create &.doc_id(popular_doc.id)
    DocVersionFactory.create &.doc_id(unpopular_doc.id)

    response = ApiClient.exec(Home::Index)

    response.body.should contain("popular-shard")
    response.body.should contain("Popular Packages")
  end

  it "includes search bar" do
    response = ApiClient.exec(Home::Index)

    response.body.should contain("Search documentation")
  end
end
