require "../../spec_helper"

# The star-ranked seeding pass: the reason the registry holds kemal rather than
# three thousand hello-worlds and kemal eventually.
#
# Everything here drives the real crawler over a real socket against recorded
# fixtures, so the query it builds, the confirmation it insists on, the row it
# writes and the cursor it leaves behind are the same code that talks to GitHub.
private def with_tokens(tokens : Hash(String, String), &)
  Discovery::Credentials.source = tokens
  begin
    yield
  ensure
    Discovery::Credentials.source = nil
  end
end

private def without_tokens(&)
  Discovery::Credentials.source = {} of String => String
  begin
    yield
  ensure
    Discovery::Credentials.source = nil
  end
end

# Answers the repository search with `repositories`, and the contents endpoint
# with a shard.yml for every repository named in `manifests` and a 404 for the
# rest. That split is the whole confirmation story: neither seed returns only
# shards, so a candidate is a shard because /contents/shard.yml says so.
private def seeded_host(
  fake : FakeHost,
  repositories : Array({String, Int32}),
  manifests : Array(String),
  total : Int32 = 1,
)
  fake.on(/\/search\/repositories/) do
    FakeHost::Response.new(body: Discovery::Fixtures.github_repository_search(repositories, total: total))
  end

  fake.on(/\/contents\/shard\.yml/) do |target, _attempt|
    slug = target.split("/repos/").last.split("/contents").first
    if manifests.includes?(slug)
      name = slug.split('/').last
      FakeHost::Response.new(body: Discovery::Fixtures.github_contents(Discovery::Fixtures.shard_yml(name)))
    else
      FakeHost::Response.new(status: 404, body: %({"message":"Not Found"}))
    end
  end
end

private def shard_for(slug : String) : Shard?
  ShardQuery.new.canonical_slug(slug).first?
end

private def high_value_state : CrawlState?
  CrawlStateQuery.new.for_host(Discovery::HighValueCrawler::STATE_KEY)
end

describe Discovery::HighValueCrawler do
  describe "seeding from the ranking" do
    it "records a starred repository that has a shard.yml, with its stars" do
      with_tokens({"GITHUB_TOKEN" => "spec-token"}) do
        FakeHost.run do |fake|
          seeded_host(fake, [{"kemalcr/kemal", 3903}], manifests: ["kemalcr/kemal"])

          report = Discovery::CrawlRunner.run_high_value(base_url: fake.base_url, max_pages: 1)

          report.discovered.should eq(1)

          shard = shard_for("github.com/kemalcr/kemal").not_nil!
          shard.name.should eq("kemal")
          shard.repository_url.should eq("https://github.com/kemalcr/kemal")
          shard.homepage_url.should eq("https://kemalcr.com")

          # The point of reading repository search rather than code search. A
          # shard this pass finds is rankable the moment it is found, months
          # before the indexer reaches it, which is what stops the front page
          # ordering by stars from being a list of shards nobody has heard of.
          shard.github_stars.should eq(3903)
          shard.github_forks.should eq(199)
        end
      end
    end

    it "asks for the ranking, not for whatever the search felt like returning" do
      with_tokens({"GITHUB_TOKEN" => "spec-token"}) do
        FakeHost.run do |fake|
          seeded_host(fake, [{"kemalcr/kemal", 3903}], manifests: ["kemalcr/kemal"])

          Discovery::CrawlRunner.run_high_value(base_url: fake.base_url, max_pages: 1)

          search = fake.requests.find(&.includes?("/search/repositories")).not_nil!
          # sort=stars is the entire reason this pass exists: code search, which
          # the exhaustive sweep is obliged to use, cannot sort at all.
          search.should contain("sort=stars")
          search.should contain("order=desc")
          search.should contain("language%3ACrystal")
        end
      end
    end

    it "skips a starred repository with no shard.yml instead of recording it" do
      with_tokens({"GITHUB_TOKEN" => "spec-token"}) do
        FakeHost.run do |fake|
          # Both are real first-page results for language:Crystal ranked by
          # stars, and only one is a shard. invidious is a YouTube front end.
          seeded_host(
            fake,
            [{"kemalcr/kemal", 3903}, {"iv-org/invidious", 22586}],
            manifests: ["kemalcr/kemal"],
          )

          report = Discovery::CrawlRunner.run_high_value(base_url: fake.base_url, max_pages: 1)

          report.discovered.should eq(1)
          report.skipped.should eq(1)
          shard_for("github.com/iv-org/invidious").should be_nil
          shard_for("github.com/kemalcr/kemal").should_not be_nil
        end
      end
    end
  end

  describe "meeting the exhaustive sweep on the same repository" do
    it "leaves one row, not two, whichever pass got there first" do
      with_tokens({"GITHUB_TOKEN" => "spec-token"}) do
        FakeHost.run do |fake|
          seeded_host(fake, [{"kemalcr/kemal", 3903}], manifests: ["kemalcr/kemal"])

          Discovery::CrawlRunner.run_high_value(base_url: fake.base_url, max_pages: 1)
          ShardQuery.new.select_count.should eq(1)

          # Now the size-window crawl reaches the same repository, which is
          # exactly what happens once its cursor gets to size:257..512. It is a
          # different endpoint, a different cursor and a different fixture, and
          # it must land on the row that already exists: identity is
          # host/owner/repo, and ShardIdentity.upsert keys on it.
          fake.on(/\/search\/code/) do
            FakeHost::Response.new(
              body: Discovery::Fixtures.github_code_search([{"kemalcr/kemal", "Fast, Effective, Simple Web Framework"}], total: 1)
            )
          end

          github = Discovery::GithubCrawler.new(base_url: fake.base_url, token: "spec-token", max_pages: 1)
          github.run

          ShardQuery.new.select_count.should eq(1)

          # And the star count survives the second pass. Code search knows
          # nothing about stars, so a crawler that wrote what it did not measure
          # would blank the figure every time the exhaustive sweep came round.
          shard_for("github.com/kemalcr/kemal").not_nil!.github_stars.should eq(3903)
        end
      end
    end

    it "keeps its own cursor, so seeding never moves the exhaustive sweep's position" do
      with_tokens({"GITHUB_TOKEN" => "spec-token"}) do
        SaveCrawlState.create!(
          host: "github.com",
          status: CrawlState::Status::PARTIAL,
          cursor: %({"current":[257,512],"page":4,"pending":[]}),
          stop_reason: CrawlState::StopReason::INTERRUPTED,
        )

        FakeHost.run do |fake|
          seeded_host(fake, [{"kemalcr/kemal", 3903}], manifests: ["kemalcr/kemal"])

          Discovery::CrawlRunner.run_high_value(base_url: fake.base_url, max_pages: 1)

          # Two cursors, two purposes. The exhaustive sweep is partway through a
          # size window and must resume there; a seeding pass that shared the row
          # would send it back to the smallest manifests on every run and it
          # would never reach the end of the host.
          CrawlStateQuery.new.for_host("github.com").not_nil!.cursor
            .should eq(%({"current":[257,512],"page":4,"pending":[]}))
          high_value_state.not_nil!.cursor.should_not be_nil
        end
      end
    end
  end

  describe "advancing across runs" do
    it "walks down the ranking instead of re-reading the same top hundred" do
      with_tokens({"GITHUB_TOKEN" => "spec-token"}) do
        FakeHost.run do |fake|
          # 1000 matches is ten pages, which is the cap: every seed in production
          # has more matches than GitHub will return.
          seeded_host(fake, [{"kemalcr/kemal", 3903}], manifests: ["kemalcr/kemal"], total: 1000)

          first = Discovery::CrawlRunner.run_high_value(base_url: fake.base_url, max_pages: 1)
          first.status.should eq(CrawlState::Status::PARTIAL)
          first.stop_reason.should eq(CrawlState::StopReason::INTERRUPTED)
          high_value_state.not_nil!.cursor.should eq(%({"seed":0,"page":2}))

          fake.requests.clear
          Discovery::CrawlRunner.run_high_value(base_url: fake.base_url, max_pages: 1)

          fake.requests.find(&.includes?("/search/repositories")).not_nil!.should contain("page=2")
          high_value_state.not_nil!.cursor.should eq(%({"seed":0,"page":3}))
        end
      end
    end

    it "moves to the second seed when the first runs out of pages" do
      with_tokens({"GITHUB_TOKEN" => "spec-token"}) do
        FakeHost.run do |fake|
          # One page per seed, so the first page exhausts the first seed.
          seeded_host(fake, [{"kemalcr/kemal", 3903}], manifests: ["kemalcr/kemal"], total: 1)

          Discovery::CrawlRunner.run_high_value(base_url: fake.base_url, max_pages: 1)
          high_value_state.not_nil!.cursor.should eq(%({"seed":1,"page":1}))

          fake.requests.clear
          Discovery::CrawlRunner.run_high_value(base_url: fake.base_url, max_pages: 1)

          # topic:crystal, which finds repositories GitHub's language detection
          # missed. Neither seed contains the other, which is why there are two.
          fake.requests.find(&.includes?("/search/repositories")).not_nil!
            .should contain("topic%3Acrystal")
        end
      end
    end

    it "ends a cycle rank-capped, and starts the ranking again on the next run" do
      with_tokens({"GITHUB_TOKEN" => "spec-token"}) do
        FakeHost.run do |fake|
          seeded_host(fake, [{"kemalcr/kemal", 3903}], manifests: ["kemalcr/kemal"], total: 1)

          report = Discovery::CrawlRunner.run_high_value(base_url: fake.base_url, max_pages: 10)

          # Never "completed exhaustive". The pass saw the top of two rankings,
          # which is not github.com, and recording it as a complete view of the
          # host is precisely what the exhaustive sweep exists to be.
          report.status.should eq(CrawlState::Status::PARTIAL)
          report.stop_reason.should eq(CrawlState::StopReason::COMPLETED_RANK_CAPPED)
          high_value_state.not_nil!.trustworthy?.should be_false

          # Cleared rather than pinned at the end. A ranking is never finished
          # the way a partition is, because the ranking moves: the next run
          # starts at the top again and sees whatever has climbed into it.
          high_value_state.not_nil!.cursor.should be_nil

          fake.requests.clear
          Discovery::CrawlRunner.run_high_value(base_url: fake.base_url, max_pages: 1)
          fake.requests.find(&.includes?("/search/repositories")).not_nil!
            .should contain("language%3ACrystal")
        end
      end
    end

    it "discards a cursor it cannot read rather than resuming from a guess" do
      Discovery::HighValueCrawler::Position.load("not json").page.should eq(1)
      Discovery::HighValueCrawler::Position.load(%({"seed":99,"page":1})).seed.should eq(0)
      Discovery::HighValueCrawler::Position.load(%({"seed":1,"page":4})).query
        .should eq("topic:crystal")
    end
  end

  describe "without GitHub's token" do
    it "refuses to seed and says which variable is missing" do
      without_tokens do
        report = Discovery::CrawlRunner.run_high_value

        report.status.should eq(CrawlState::Status::FAILED)
        report.stop_reason.should eq(CrawlState::StopReason::TOKEN_MISSING)
        report.error.to_s.should contain("GITHUB_TOKEN")
        report.requests.should eq(0)

        # Recorded on its own row, named so an operator can tell which of the two
        # GitHub passes refused.
        high_value_state.not_nil!.host.should eq("github.com/high-value")
      end
    end
  end
end
