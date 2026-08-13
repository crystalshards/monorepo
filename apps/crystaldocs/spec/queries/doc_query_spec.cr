require "../spec_helper"

describe DocQuery do
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
