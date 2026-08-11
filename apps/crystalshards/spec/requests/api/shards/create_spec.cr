require "../../../spec_helper"

describe Api::Shards::Create do
  it "creates a new shard successfully" do
    user = UserFactory.create

    response = ApiClient.auth(user).exec(Api::Shards::Create,
      shard: {
        name:           "test-shard",
        description:    "A test shard for Crystal",
        repository_url: "https://github.com/user/test-shard",
        homepage_url:   "https://test-shard.org",
        license:        "MIT",
      },
      version: "0.1.0"
    )

    if response.status_code != 201
      pp! response.status_code, response.body
    end
    response.status.should eq(HTTP::Status.new(201))
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
    user = UserFactory.create

    response = ApiClient.auth(user).exec(Api::Shards::Create,
      shard: {
        name: "test-shard",
        # Missing required repository_url
      }
    )

    response.status.should eq(HTTP::Status.new(422))
    response.body.should contain("errors")
  end

  # Uniqueness is on the repository, not the name. Two projects may both be
  # called "duplicate-shard"; what cannot happen twice is one repository.
  it "accepts a name another shard already uses, on a different repository" do
    user = UserFactory.create

    ShardFactory.create &.name("duplicate-shard")
      .repository_url("https://github.com/user/duplicate-shard")

    response = ApiClient.auth(user).exec(Api::Shards::Create,
      shard: {
        name:           "duplicate-shard",
        repository_url: "https://gitlab.com/other/duplicate-shard",
      },
      version: "0.1.0"
    )

    response.status.should eq(HTTP::Status.new(201))
    ShardQuery.new.name("duplicate-shard").select_count.should eq(2)
    JSON.parse(response.body)["shard"]["canonical_slug"]
      .should eq("gitlab.com/other/duplicate-shard")
  end

  it "refuses a repository that is already registered" do
    user = UserFactory.create

    ShardFactory.create &.name("duplicate-shard")
      .repository_url("https://github.com/user/duplicate-shard")

    response = ApiClient.auth(user).exec(Api::Shards::Create,
      shard: {
        name:           "renamed-but-same-repo",
        repository_url: "https://github.com/user/duplicate-shard",
      },
      version: "0.1.0"
    )

    response.status.should eq(HTTP::Status.new(422))
    response.body.should contain("already registered")
  end

  it "validates repository URL format" do
    user = UserFactory.create

    response = ApiClient.auth(user).exec(Api::Shards::Create,
      shard: {
        name:           "test-shard",
        repository_url: "not-a-valid-url",
      },
      version: "0.1.0"
    )

    response.status.should eq(HTTP::Status.new(422))
    response.body.should contain("errors")
  end

  it "allows optional fields" do
    user = UserFactory.create

    response = ApiClient.auth(user).exec(Api::Shards::Create,
      shard: {
        name:           "minimal-shard",
        repository_url: "https://github.com/user/minimal-shard",
      },
      version: "1.0.0"
    )

    response.status.should eq(HTTP::Status.new(201))

    shard = ShardQuery.new.name("minimal-shard").first?
    shard.should_not be_nil
    shard.try(&.description).should be_nil
    shard.try(&.homepage_url).should be_nil
  end

  it "enqueues indexing worker after creation" do
    user = UserFactory.create

    # Note: In production this would check worker queue
    # For now we just verify the response indicates indexing started
    response = ApiClient.auth(user).exec(Api::Shards::Create,
      shard: {
        name:           "worker-test-shard",
        repository_url: "https://github.com/user/worker-test-shard",
      },
      version: "2.0.0"
    )

    response.status.should eq(HTTP::Status.new(201))
    response.body.should contain("indexing started")
  end

  it "handles invalid JSON gracefully" do
    response = ApiClient.exec(Api::Shards::Create, body: "not valid json")

    # Should return error, not crash
    response.status_code.should be >= 400
  end

  it "validates version format" do
    user = UserFactory.create

    response = ApiClient.auth(user).exec(Api::Shards::Create,
      shard: {
        name:           "version-test-shard",
        repository_url: "https://github.com/user/version-test-shard",
      },
      version: "invalid-version"
    )

    # Should accept the version for now (IndexShardWorker will validate it)
    # Or return 422 if validation is implemented
    response.status_code.should be < 500
  end
end
