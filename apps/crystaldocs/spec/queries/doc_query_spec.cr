require "../spec_helper"

describe DocQuery do
  describe "#search" do
    it "finds docs by package name" do
      http_doc = DocFactory.create &.package_name("http-client")
      db_doc = DocFactory.create &.package_name("crystal-db")

      results = DocQuery.new.search("http").results

      results.should contain(http_doc)
      results.should_not contain(db_doc)
    end

    it "finds docs by description" do
      doc = DocFactory.create &.package_name("mylib")
        .description("HTTP client library for Crystal")

      results = DocQuery.new.search("HTTP").results

      results.should contain(doc)
    end

    it "is case insensitive" do
      doc = DocFactory.create &.package_name("MyLib")

      results = DocQuery.new.search("mylib").results
      results.should contain(doc)
    end

    it "returns all docs when query is nil" do
      doc1 = DocFactory.create
      doc2 = DocFactory.create

      results = DocQuery.new.search(nil).results

      results.size.should eq(2)
    end

    it "returns all docs when query is empty string" do
      doc1 = DocFactory.create
      doc2 = DocFactory.create

      results = DocQuery.new.search("").results

      results.size.should eq(2)
    end
  end

  describe "#recently_updated" do
    it "orders docs by last_updated_at descending" do
      old_doc = DocFactory.create &.last_updated_at(Time.utc - 10.days)
      recent_doc = DocFactory.create &.last_updated_at(Time.utc)
      middle_doc = DocFactory.create &.last_updated_at(Time.utc - 5.days)

      results = DocQuery.new.recently_updated.results

      results.first.should eq(recent_doc)
      results[1].should eq(middle_doc)
      results.last.should eq(old_doc)
    end
  end

  describe "#popular" do
    it "orders docs by total_views descending" do
      unpopular = DocFactory.create &.total_views(10)
      popular = DocFactory.create &.total_views(1000)
      medium = DocFactory.create &.total_views(100)

      results = DocQuery.new.popular.results

      results.first.should eq(popular)
      results[1].should eq(medium)
      results.last.should eq(unpopular)
    end
  end

  describe "#preload_versions" do
    it "preloads doc_versions to avoid N+1 queries" do
      doc = DocFactory.create
      version = DocVersionFactory.create &.doc_id(doc.id)

      results = DocQuery.new.preload_versions.results

      # Should not trigger additional query when accessing versions
      results.first.doc_versions.should contain(version)
    end
  end

  describe "chaining queries" do
    it "allows chaining multiple query methods" do
      popular_http = DocFactory.create &.package_name("http-client")
        .total_views(1000)
        .last_updated_at(Time.utc)
      unpopular_http = DocFactory.create &.package_name("http-server")
        .total_views(10)
        .last_updated_at(Time.utc - 5.days)
      popular_db = DocFactory.create &.package_name("crystal-db")
        .total_views(500)

      results = DocQuery.new
        .search("http")
        .popular
        .results

      results.first.should eq(popular_http)
      results.last.should eq(unpopular_http)
      results.should_not contain(popular_db)
    end
  end
end
