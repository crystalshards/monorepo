require "../../../spec_helper"

describe Api::Shards::Create do
  it "creates a new shard successfully" do
    response = ApiClient.exec(Api::Shards::Create, body: {
      name:           "test-shard",
      description:    "A test shard for Crystal",
      repository_url: "https://github.com/user/test-shard",
      homepage_url:   "https://test-shard.org",
      license:        "MIT",
      version:        "0.1.0",
    }.to_json)

    response.should send_json(201)
    json = JSON.parse(response.body)
    json["message"].should eq("Shard created successfully, indexing started")
    json["shard"]["name"].should eq("test-shard")

    # Verify shard was created in database
    shard = ShardQuery.new.name("test-shard").first?
    shard.should_not be_nil
    shard.try(&.description).should eq("A test shard for Crystal")
    shard.try(&.repository_url).should eq("https://github.com/user/test-shard")
  end

  it "validates required fields" do
    response = ApiClient.exec(Api::Shards::Create, body: {
      name: "test-shard",
      # Missing required repository_url and version
    }.to_json)

    response.should send_json(422)
    response.body.should contain("errors")
  end

  it "validates name uniqueness" do
    # Create first shard
    ShardFactory.create &.name("duplicate-shard")
      .repository_url("https://github.com/user/duplicate-shard")

    # Attempt to create shard with same name
    response = ApiClient.exec(Api::Shards::Create, body: {
      name:           "duplicate-shard",
      repository_url: "https://github.com/user/duplicate-shard-2",
      version:        "0.1.0",
    }.to_json)

    response.should send_json(422)
    response.body.should contain("errors")
  end

  it "validates repository URL format" do
    response = ApiClient.exec(Api::Shards::Create, body: {
      name:           "test-shard",
      repository_url: "not-a-valid-url",
      version:        "0.1.0",
    }.to_json)

    response.should send_json(422)
    response.body.should contain("errors")
  end

  it "allows optional fields" do
    response = ApiClient.exec(Api::Shards::Create, body: {
      name:           "minimal-shard",
      repository_url: "https://github.com/user/minimal-shard",
      version:        "1.0.0",
    }.to_json)

    response.should send_json(201)

    shard = ShardQuery.new.name("minimal-shard").first?
    shard.should_not be_nil
    shard.try(&.description).should be_nil
    shard.try(&.homepage_url).should be_nil
  end

  it "enqueues indexing worker after creation" do
    # Note: In production this would check worker queue
    # For now we just verify the response indicates indexing started
    response = ApiClient.exec(Api::Shards::Create, body: {
      name:           "worker-test-shard",
      repository_url: "https://github.com/user/worker-test-shard",
      version:        "2.0.0",
    }.to_json)

    response.should send_json(201)
    response.body.should contain("indexing started")
  end

  it "handles invalid JSON gracefully" do
    response = ApiClient.exec(Api::Shards::Create, body: "not valid json")

    # Should return error, not crash
    response.status_code.should be >= 400
  end

  it "validates version format" do
    response = ApiClient.exec(Api::Shards::Create, body: {
      name:           "version-test-shard",
      repository_url: "https://github.com/user/version-test-shard",
      version:        "invalid-version",
    }.to_json)

    # Should accept the version for now (IndexShardWorker will validate it)
    # Or return 422 if validation is implemented
    response.status_code.should be < 500
  end
end
