require "../spec_helper"

describe DocQuery do
  describe "#search" do
    it "finds docs by package name" do
      http_doc = DocFactory.create &.package_name("http-client")
      db_doc = DocFactory.create &.package_name("database")

      results = DocQuery.new.search("http")

      results.results.should contain(http_doc)
      results.results.should_not contain(db_doc)
    end

    it "finds docs by description" do
      doc1 = DocFactory.create &.package_name("client")
        .description("HTTP client library")

      doc2 = DocFactory.create &.package_name("server")
        .description("Database server")

      results = DocQuery.new.search("HTTP")

      results.results.should contain(doc1)
      results.results.should_not contain(doc2)
    end

    it "is case insensitive" do
      doc = DocFactory.create &.package_name("MyPackage")
        .description("Test Package")

      results_lower = DocQuery.new.search("mypackage")
      results_upper = DocQuery.new.search("MYPACKAGE")

      results_lower.results.should contain(doc)
      results_upper.results.should contain(doc)
    end

    it "returns all docs when query is nil" do
      doc1 = DocFactory.create &.package_name("package1")
      doc2 = DocFactory.create &.package_name("package2")

      results = DocQuery.new.search(nil)

      results.results.size.should eq(2)
    end

    it "returns all docs when query is empty" do
      doc1 = DocFactory.create &.package_name("package1")
      doc2 = DocFactory.create &.package_name("package2")

      results = DocQuery.new.search("")

      results.results.size.should eq(2)
    end

    it "handles partial matches" do
      doc = DocFactory.create &.package_name("crystal-http-client")

      results = DocQuery.new.search("http")

      results.results.should contain(doc)
    end
  end

  describe "#with_versions" do
    it "preloads doc versions to avoid N+1 queries" do
      doc = DocFactory.create &.package_name("test-package")

      version1 = DocVersionFactory.create &.doc_id(doc.id)
      version2 = DocVersionFactory.create &.doc_id(doc.id)

      docs = DocQuery.new.with_versions.results

      docs.first.doc_versions.should_not be_nil
      docs.first.doc_versions.size.should eq(2)
    end
  end

  describe "#recently_updated" do
    it "orders docs by last_updated_at descending" do
      old_doc = DocFactory.create &.package_name("old")
        .last_updated_at(Time.utc - 30.days)

      new_doc = DocFactory.create &.package_name("new")
        .last_updated_at(Time.utc - 1.hour)

      results = DocQuery.new.recently_updated.results

      results.first.should eq(new_doc)
      results.last.should eq(old_doc)
    end
  end

  describe "#popular" do
    it "orders docs by total_views descending" do
      unpopular = DocFactory.create &.package_name("unpopular")
        .total_views(10)

      popular = DocFactory.create &.package_name("popular")
        .total_views(1000)

      results = DocQuery.new.popular.results

      results.first.should eq(popular)
      results.last.should eq(unpopular)
    end
  end

  describe "#published" do
    it "only returns docs with current_version set" do
      published = DocFactory.create &.package_name("published")
        .current_version("1.0.0")

      unpublished = DocFactory.create &.package_name("unpublished")
        .current_version(nil)

      results = DocQuery.new.published.results

      results.should contain(published)
      results.should_not contain(unpublished)
    end
  end

  describe "chaining methods" do
    it "allows combining search with sorting" do
      http_old = DocFactory.create &.package_name("http-old")
        .last_updated_at(Time.utc - 30.days)

      http_new = DocFactory.create &.package_name("http-new")
        .last_updated_at(Time.utc - 1.hour)

      db_new = DocFactory.create &.package_name("database")
        .last_updated_at(Time.utc - 2.hours)

      results = DocQuery.new
        .search("http")
        .recently_updated
        .results

      results.size.should eq(2)
      results.first.should eq(http_new)
      results.last.should eq(http_old)
    end

    it "allows combining published filter with popularity" do
      published_popular = DocFactory.create &.package_name("popular")
        .current_version("1.0.0")
        .total_views(1000)

      published_unpopular = DocFactory.create &.package_name("unpopular")
        .current_version("1.0.0")
        .total_views(10)

      unpublished = DocFactory.create &.package_name("no-version")
        .current_version(nil)
        .total_views(500)

      results = DocQuery.new
        .published
        .popular
        .results

      results.size.should eq(2)
      results.first.should eq(published_popular)
      results.should_not contain(unpublished)
    end
  end
end
