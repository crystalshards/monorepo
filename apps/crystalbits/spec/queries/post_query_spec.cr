require "../spec_helper"

describe PostQuery do
  describe "#published" do
    it "returns only published posts" do
      published = PostFactory.create &.published_at(Time.utc - 1.day)
      unpublished = PostFactory.create &.published_at(nil)

      results = PostQuery.new.published.to_a

      results.should contain(published)
      results.should_not contain(unpublished)
    end

    it "excludes future posts" do
      past_post = PostFactory.create &.published_at(Time.utc - 1.day)
      future_post = PostFactory.create &.published_at(Time.utc + 1.day)

      results = PostQuery.new.published.to_a

      results.should contain(past_post)
      results.should_not contain(future_post)
    end
  end

  describe "#featured_only" do
    it "returns only featured posts" do
      featured = PostFactory.create &.featured(true).published_at(Time.utc - 1.day)
      not_featured = PostFactory.create &.featured(false).published_at(Time.utc - 2.days)

      results = PostQuery.new.published.featured_only.to_a

      results.should contain(featured)
      results.should_not contain(not_featured)
    end
  end

  describe "#by_tag" do
    it "finds posts with specific tag" do
      crystal_post = PostFactory.create &.tags(["crystal", "tutorial"]).published_at(Time.utc - 1.day)
      ruby_post = PostFactory.create &.tags(["ruby", "tutorial"]).published_at(Time.utc - 2.days)

      results = PostQuery.new.published.by_tag("crystal").to_a

      results.should contain(crystal_post)
      results.should_not contain(ruby_post)
    end

    it "finds posts with tag in any position" do
      first = PostFactory.create &.tags(["crystal", "web"]).published_at(Time.utc - 1.day)
      middle = PostFactory.create &.tags(["tutorial", "crystal", "advanced"]).published_at(Time.utc - 2.days)
      last = PostFactory.create &.tags(["web", "tutorial", "crystal"]).published_at(Time.utc - 3.days)

      results = PostQuery.new.published.by_tag("crystal").to_a

      results.should contain(first)
      results.should contain(middle)
      results.should contain(last)
    end
  end

  describe "#search" do
    it "finds posts by title" do
      matching = PostFactory.create &.title("Building Web Apps").published_at(Time.utc - 1.day)
      non_matching = PostFactory.create &.title("Database Tutorial").published_at(Time.utc - 2.days)

      results = PostQuery.new.published.search("Web Apps").to_a

      results.should contain(matching)
      results.should_not contain(non_matching)
    end

    it "finds posts by content" do
      matching = PostFactory.create do |p|
        p.title("Guide")
        p.content("Learn about Crystal web frameworks")
        p.published_at(Time.utc - 1.day)
      end
      non_matching = PostFactory.create do |p|
        p.title("Tutorial")
        p.content("Learn about PostgreSQL")
        p.published_at(Time.utc - 2.days)
      end

      results = PostQuery.new.published.search("web frameworks").to_a

      results.should contain(matching)
      results.should_not contain(non_matching)
    end

    it "is case insensitive" do
      post = PostFactory.create &.title("Crystal Tutorial").published_at(Time.utc - 1.day)

      results = PostQuery.new.published.search("crystal").to_a
      results.should contain(post)

      results = PostQuery.new.published.search("CRYSTAL").to_a
      results.should contain(post)

      results = PostQuery.new.published.search("CrYsTaL").to_a
      results.should contain(post)
    end

    it "supports partial matches" do
      post = PostFactory.create &.title("Understanding Crystal").published_at(Time.utc - 1.day)

      results = PostQuery.new.published.search("stand").to_a

      results.should contain(post)
    end
  end

  describe "#recent" do
    it "orders posts by published_at descending" do
      oldest = PostFactory.create &.published_at(Time.utc - 5.days)
      middle = PostFactory.create &.published_at(Time.utc - 3.days)
      newest = PostFactory.create &.published_at(Time.utc - 1.day)

      results = PostQuery.new.published.recent.to_a

      results[0].id.should eq(newest.id)
      results[1].id.should eq(middle.id)
      results[2].id.should eq(oldest.id)
    end
  end

  describe "#popular" do
    it "orders posts by view count descending" do
      low_views = PostFactory.create &.view_count(10).published_at(Time.utc - 1.day)
      medium_views = PostFactory.create &.view_count(100).published_at(Time.utc - 2.days)
      high_views = PostFactory.create &.view_count(1000).published_at(Time.utc - 3.days)

      results = PostQuery.new.published.popular.to_a

      results[0].id.should eq(high_views.id)
      results[1].id.should eq(medium_views.id)
      results[2].id.should eq(low_views.id)
    end
  end

  describe "chaining" do
    it "can chain multiple query methods" do
      matching = PostFactory.create do |p|
        p.title("Crystal Web Tutorial")
        p.tags(["crystal", "web"])
        p.published_at(Time.utc - 1.day)
        p.featured(true)
      end
      wrong_tag = PostFactory.create do |p|
        p.title("Ruby Web Tutorial")
        p.tags(["ruby", "web"])
        p.published_at(Time.utc - 2.days)
        p.featured(true)
      end
      not_featured = PostFactory.create do |p|
        p.title("Crystal Web Tutorial")
        p.tags(["crystal", "web"])
        p.published_at(Time.utc - 3.days)
        p.featured(false)
      end

      results = PostQuery.new
        .published
        .featured_only
        .by_tag("crystal")
        .search("Web")
        .to_a

      results.should contain(matching)
      results.should_not contain(wrong_tag)
      results.should_not contain(not_featured)
    end
  end
end
