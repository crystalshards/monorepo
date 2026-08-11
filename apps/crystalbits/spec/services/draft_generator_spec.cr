require "../spec_helper"

private def with_generator_config(api_key : String?, model : String?, &)
  DraftGenerator.configure do |settings|
    settings.api_key = api_key
    settings.model = model
  end

  yield
ensure
  DraftGenerator.configure do |settings|
    settings.api_key = nil
    settings.model = nil
  end
end

describe DraftGenerator do
  describe "with nothing configured" do
    it "reports itself unconfigured" do
      with_generator_config(nil, nil) do
        DraftGenerator.configured?.should be_false
        DraftGenerator.missing_configuration.should eq(["BITS_MODEL_API_KEY", "BITS_MODEL"])
      end
    end

    # Inert, not broken and not pretending. No network call, no exception, no
    # placeholder row that an editor would have to work out the meaning of.
    it "writes nothing and says why" do
      with_generator_config(nil, nil) do
        result = DraftGenerator.run

        result.status.should eq(DraftGenerator::Status::NotConfigured)
        result.drafts.should be_empty
        result.generated?.should be_false
        result.message.should contain("BITS_MODEL_API_KEY")
        result.message.should contain("No drafts were written")

        ContentItemQuery.new.select_count.should eq(0)
      end
    end
  end

  describe "with only half the configuration" do
    it "stays off when the model is missing" do
      with_generator_config("sk-test", nil) do
        DraftGenerator.configured?.should be_false
        DraftGenerator.missing_configuration.should eq(["BITS_MODEL"])

        result = DraftGenerator.run
        result.status.should eq(DraftGenerator::Status::NotConfigured)
        ContentItemQuery.new.select_count.should eq(0)
      end
    end

    it "stays off when the key is missing" do
      with_generator_config(nil, "claude-opus-5") do
        DraftGenerator.configured?.should be_false
        DraftGenerator.missing_configuration.should eq(["BITS_MODEL_API_KEY"])

        DraftGenerator.run.status.should eq(DraftGenerator::Status::NotConfigured)
        ContentItemQuery.new.select_count.should eq(0)
      end
    end
  end

  describe "the drafts it produces" do
    # Exercises the storage path the generator uses, without a model API key.
    it "lands in draft state, labelled, with sources, and out of the public index" do
      item, _ = ContentIngestor.upsert(
        source_url: "https://www.reddit.com/r/crystal_programming/comments/1v9pg4y/",
        origin: ContentItem::Origin::GENERATED,
        title: "A garbage collector for Crystal, written in Crystal",
        summary: "Our own summary.",
        body: "Our own words.",
        attribution: DraftGenerator::ATTRIBUTION,
        machine_drafted: true,
        source_urls: [
          "https://www.reddit.com/r/crystal_programming/comments/1v9pg4y/",
          "https://www.reddit.com/r/crystal_programming/comments/1vf7576/",
        ],
      )

      item.state.should eq(ContentItem::State::DRAFT)
      item.machine_drafted.should be_true
      item.origin_label.should eq("Machine-drafted by CrystalBits")
      item.source_urls.size.should eq(2)

      ContentItemQuery.new.publicly_visible.select_count.should eq(0)
      BrowserClient.exec(News::Index).body.should_not contain("A garbage collector for Crystal")
    end
  end
end

private def discussion(title : String, body : String = "", subreddit : String = "programming")
  RedditHarvest::Discussion.new(
    id: "abc",
    subreddit: subreddit,
    title: title,
    author: "someone",
    permalink: "https://www.reddit.com/r/#{subreddit}/comments/abc/",
    score: 1,
    comment_count: 0,
    created_at: nil,
    body: body,
  )
end

describe RedditHarvest do
  it "accepts anything from a Crystal subreddit" do
    harvest = RedditHarvest.new

    harvest.crystal_related?(discussion("Anything at all", subreddit: "crystal_programming")).should be_true
  end

  it "requires a language signal anywhere else" do
    harvest = RedditHarvest.new

    harvest.crystal_related?(discussion("My crystal ball says buy")).should be_false
    harvest.crystal_related?(discussion("crystal-lang 1.21 released")).should be_true
    harvest.crystal_related?(discussion("Kemal 1.12 adds SSE")).should be_true
  end

  it "gives the drafting step a brief that names its source" do
    brief = discussion("gcry benchmarks", body: "Some numbers.", subreddit: "crystal_programming").brief

    brief.should contain("gcry benchmarks")
    brief.should contain("https://www.reddit.com/r/crystal_programming/comments/abc/")
    brief.should contain("never to be quoted")
  end
end
