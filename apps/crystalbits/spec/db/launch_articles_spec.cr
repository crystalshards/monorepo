require "../spec_helper"

# The four launch announcements, asserted at the source rather than in the
# database.
#
# The rows themselves cannot be checked here: the suite truncates every table
# between examples, so a migration's rows are gone by the time an example
# runs, and a spec that queried for them would pass only by accident on the
# one machine where the cleaner had not fired yet.
#
# What is worth pinning is the contract, and it is a real one. The
# announcement bar on all four sites links to these exact slugs, and the
# bodies are files that a person edits. A renamed slug, a deleted file or an
# em-dash smuggled into an article are all things this catches and a reader
# would otherwise find first.
describe PublishLaunchArticles::V00000000000005 do
  articles = PublishLaunchArticles::V00000000000005::ARTICLES

  it "publishes exactly one announcement per property" do
    articles.map { |article| article[:slug] }.sort.should eq([
      "a-place-to-write-about-crystal",
      "documentation-for-every-shard",
      "finding-every-crystal-shard",
      "where-crystal-work-gets-posted",
    ])
  end

  it "tags each announcement with the property it announces" do
    tags = articles.to_h { |article| {article[:slug], article[:tag]} }

    tags["finding-every-crystal-shard"].should eq("crystalshards")
    tags["documentation-for-every-shard"].should eq("crystaldocs")
    tags["where-crystal-work-gets-posted"].should eq("crystalgigs")
    tags["a-place-to-write-about-crystal"].should eq("crystalbits")
  end

  it "gives every announcement a title, an excerpt and a body with something in it" do
    articles.each do |article|
      article[:title].should_not be_empty
      article[:excerpt].should_not be_empty
      # Short enough to be a real threshold, long enough that an empty or
      # truncated file trips it. The shortest of the four is about 900 bytes.
      article[:body].size.should be > 500
    end
  end

  # The one that would have shipped: an em-dash is the clearest sign a machine
  # wrote the copy, and the house rule forbids it everywhere. An en-dash counts
  # the same way.
  it "keeps em-dashes and en-dashes out of every announcement" do
    articles.each do |article|
      {article[:title], article[:excerpt], article[:body]}.each do |text|
        text.should_not contain("\u2014")
        text.should_not contain("\u2013")
      end
    end
  end

  # The migration builds its SQL with dollar quoting, so a body containing the
  # tag would close the literal early and leave the rest of the article being
  # read as SQL. The migration raises on this; the spec is what makes sure a
  # fifth article does not discover that in production.
  it "keeps the dollar quote tag out of every announcement" do
    tag = PublishLaunchArticles::V00000000000005::BODY_TAG

    articles.each do |article|
      article[:body].should_not contain(tag)
      article[:title].should_not contain(tag)
      article[:excerpt].should_not contain(tag)
    end
  end
end
