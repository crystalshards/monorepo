require "../../../spec_helper"

describe Api::Ads::Index do
  it "puts featured jobs first, then the newest within each tier" do
    # Created out of order on purpose. If the action ever loses one of its two
    # order_by calls this fails, which a single-tier fixture would not catch.
    JobFactory.create &.title("plain old").featured(false).published_at(3.days.ago)
    JobFactory.create &.title("plain new").featured(false).published_at(1.hour.ago)
    JobFactory.create &.title("featured old").featured(true).published_at(10.days.ago)
    JobFactory.create &.title("featured new").featured(true).published_at(2.days.ago)

    response = ApiClient.exec(Api::Ads::Index, limit: "4")

    titles = JSON.parse(response.body)["jobs"].as_a.map(&.["title"].as_s)
    titles.should eq(["featured new", "featured old", "plain new", "plain old"])
  end

  it "returns three jobs when the caller asks for no limit" do
    5.times { |i| JobFactory.create &.title("job #{i}") }

    response = ApiClient.exec(Api::Ads::Index)

    JSON.parse(response.body)["jobs"].as_a.size.should eq(3)
  end

  it "caps the limit so a caller cannot pull the whole board into an ad strip" do
    15.times { |i| JobFactory.create &.title("job #{i}") }

    response = ApiClient.exec(Api::Ads::Index, limit: "500")

    JSON.parse(response.body)["jobs"].as_a.size.should eq(Api::Ads::Index::MAX_LIMIT)
  end

  it "falls back to the default rather than erroring on junk limits" do
    5.times { |i| JobFactory.create &.title("job #{i}") }

    JSON.parse(ApiClient.exec(Api::Ads::Index, limit: "banana").body)["jobs"]
      .as_a.size.should eq(3)
    # Zero and negative would otherwise reach LIMIT and return an empty strip,
    # which reads on the consuming sites as "the board has no jobs".
    JSON.parse(ApiClient.exec(Api::Ads::Index, limit: "0").body)["jobs"]
      .as_a.size.should eq(1)
    JSON.parse(ApiClient.exec(Api::Ads::Index, limit: "-3").body)["jobs"]
      .as_a.size.should eq(1)
  end

  it "excludes jobs that are not advertisable" do
    JobFactory.create &.title("live")
    JobFactory.create &.title("inactive").active(false)
    JobFactory.create &.title("unpublished").published_at(nil)
    JobFactory.create &.title("expired").expires_at(1.day.ago)

    response = ApiClient.exec(Api::Ads::Index, limit: "10")

    titles = JSON.parse(response.body)["jobs"].as_a.map(&.["title"].as_s)
    titles.should eq(["live"])
  end

  it "stops advertising a posting that was delisted upstream, even if it is active" do
    JobFactory.create &.title("live")
    # Deliberately still active: the delisting stamp is the durable fact, and
    # three other sites cannot check whether the role reopened.
    JobFactory.create &.title("delisted").active(true).delisted_at(1.day.ago)

    response = ApiClient.exec(Api::Ads::Index, limit: "10")

    titles = JSON.parse(response.body)["jobs"].as_a.map(&.["title"].as_s)
    titles.should eq(["live"])
  end

  it "serves only the six advertising fields" do
    JobFactory.create &.title("Senior Crystal Developer")
      .company_name("Crystal Corp")
      .location("Denver, CO")
      .remote(true)
      .featured(true)

    response = ApiClient.exec(Api::Ads::Index)
    ad = JSON.parse(response.body)["jobs"].as_a.first.as_h

    ad.keys.sort!.should eq(["company", "featured", "location", "remote", "title", "url"])
    ad["title"].should eq("Senior Crystal Developer")
    ad["company"].should eq("Crystal Corp")
    ad["location"].should eq("Denver, CO")
    ad["remote"].should eq(true)
    ad["featured"].should eq(true)
    # The board's own page, not the employer's apply_url. Sending readers to
    # an employer's site would make the ad useless to CrystalGigs and would
    # put an employer-supplied URL into three other sites' markup.
    ad["url"].as_s.should end_with("/jobs/#{JobQuery.new.first.id}")
    ad["url"].as_s.should_not contain("crystalcorp.example.com")
  end

  it "is publicly cacheable so three sites rendering on every request do not each hit the database" do
    JobFactory.create

    response = ApiClient.exec(Api::Ads::Index)

    cache_control = response.headers["Cache-Control"]
    cache_control.should contain("public")
    cache_control.should contain("max-age=#{Api::Ads::Index::CACHE_SECONDS}")
  end

  it "needs no auth token, because every consuming site is anonymous" do
    JobFactory.create

    ApiClient.exec(Api::Ads::Index).status_code.should eq(200)
  end

  it "returns an empty list rather than an error when the board has nothing to advertise" do
    response = ApiClient.exec(Api::Ads::Index)

    response.status_code.should eq(200)
    JSON.parse(response.body)["jobs"].as_a.should be_empty
  end
end
