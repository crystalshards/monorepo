require "../../../spec_helper"
require "digest/sha256"

describe Api::Shards::Upload do
  pending "uploads a package with multipart form data" do
    user = UserFactory.create

    # Create test package content
    package_content = "fake tar.gz content for testing"
    checksum = Digest::SHA256.hexdigest(package_content)

    # Build multipart form data
    io = IO::Memory.new
    builder = HTTP::FormData::Builder.new(io, "boundary123")

    builder.field("name", "multipart-shard")
    builder.field("version", "1.0.0")
    builder.field("description", "A test shard uploaded via multipart")
    builder.field("repository_url", "https://github.com/user/multipart-shard")
    builder.field("license", "MIT")
    builder.field("checksum", checksum)

    builder.file(
      "package",
      IO::Memory.new(package_content),
      HTTP::FormData::FileMetadata.new(filename: "multipart-shard-1.0.0.tar.gz")
    )

    builder.finish

    response = ApiClient.auth_multipart(user).headers(
      "Content-Type": "multipart/form-data; boundary=boundary123"
    ).exec(
      Api::Shards::Upload,
      body: io.to_s
    )

    response.should send_json(201)
    json = JSON.parse(response.body)
    json["message"].should eq("Shard uploaded successfully")
    json["shard"]["name"].should eq("multipart-shard")
    json["version"]["version"].should eq("1.0.0")
    json["checksum"].should eq(checksum)

    # Verify shard was created in database
    shard = ShardQuery.new.name("multipart-shard").first?
    shard.should_not be_nil
    shard.try(&.description).should eq("A test shard uploaded via multipart")
  end

  pending "validates required fields are present" do
    user = UserFactory.create
    io = IO::Memory.new
    builder = HTTP::FormData::Builder.new(io, "boundary123")

    # Only provide name (missing version, repository_url, package)
    builder.field("name", "incomplete-shard")

    builder.finish

    response = ApiClient.auth_multipart(user).headers(
      "Content-Type": "multipart/form-data; boundary=boundary123"
    ).exec(
      Api::Shards::Upload,
      body: io.to_s
    )

    response.should send_json(400)
    response.body.should contain("Missing required fields")
  end

  pending "validates package file extension" do
    package_content = "fake content"
    user = UserFactory.create

    io = IO::Memory.new
    builder = HTTP::FormData::Builder.new(io, "boundary123")

    builder.field("name", "bad-extension-shard")
    builder.field("version", "1.0.0")
    builder.field("repository_url", "https://github.com/user/bad-extension-shard")

    builder.file(
      "package",
      IO::Memory.new(package_content),
      HTTP::FormData::FileMetadata.new(filename: "package.zip")
    )

    builder.finish

    response = ApiClient.auth_multipart(user).headers(
      "Content-Type": "multipart/form-data; boundary=boundary123"
    ).exec(
      Api::Shards::Upload,
      body: io.to_s
    )

    response.should send_json(400)
    response.body.should contain("must be a .tar.gz archive")
  end

  pending "validates checksum when provided" do
    package_content = "fake tar.gz content"
    wrong_checksum = "0000000000000000000000000000000000000000000000000000000000000000"
    user = UserFactory.create

    io = IO::Memory.new
    builder = HTTP::FormData::Builder.new(io, "boundary123")

    builder.field("name", "checksum-test-shard")
    builder.field("version", "1.0.0")
    builder.field("repository_url", "https://github.com/user/checksum-test-shard")
    builder.field("checksum", wrong_checksum)

    builder.file(
      "package",
      IO::Memory.new(package_content),
      HTTP::FormData::FileMetadata.new(filename: "package.tar.gz")
    )

    builder.finish

    response = ApiClient.auth_multipart(user).headers(
      "Content-Type": "multipart/form-data; boundary=boundary123"
    ).exec(
      Api::Shards::Upload,
      body: io.to_s
    )

    response.should send_json(400)
    json = JSON.parse(response.body)
    json["error"].should eq("Checksum mismatch")
    json["expected_checksum"].should eq(wrong_checksum)
    json["actual_checksum"].should_not eq(wrong_checksum)
  end

  pending "computes checksum when not provided" do
    package_content = "fake tar.gz content"
    user = UserFactory.create

    io = IO::Memory.new
    builder = HTTP::FormData::Builder.new(io, "boundary123")

    builder.field("name", "auto-checksum-shard")
    builder.field("version", "1.0.0")
    builder.field("repository_url", "https://github.com/user/auto-checksum-shard")

    builder.file(
      "package",
      IO::Memory.new(package_content),
      HTTP::FormData::FileMetadata.new(filename: "package.tar.gz")
    )

    builder.finish

    response = ApiClient.auth_multipart(user).headers(
      "Content-Type": "multipart/form-data; boundary=boundary123"
    ).exec(
      Api::Shards::Upload,
      body: io.to_s
    )

    response.should send_json(201)
    json = JSON.parse(response.body)
    json["checksum"].should eq(Digest::SHA256.hexdigest(package_content))
  end

  it "rejects non-multipart content type" do
    user = UserFactory.create

    response = ApiClient.auth(user).exec(
      Api::Shards::Upload,
      headers: HTTP::Headers{"Content-Type" => "application/json"},
      body: {name: "json-shard"}.to_json
    )

    response.should send_json(400)
    response.body.should contain("Content-Type must be multipart/form-data")
  end

  pending "handles optional fields correctly" do
    package_content = "minimal package content"
    user = UserFactory.create
    checksum = Digest::SHA256.hexdigest(package_content)

    io = IO::Memory.new
    builder = HTTP::FormData::Builder.new(io, "boundary123")

    builder.field("name", "minimal-multipart-shard")
    builder.field("version", "1.0.0")
    builder.field("repository_url", "https://github.com/user/minimal-multipart-shard")

    builder.file(
      "package",
      IO::Memory.new(package_content),
      HTTP::FormData::FileMetadata.new(filename: "package.tar.gz")
    )

    builder.finish

    response = ApiClient.auth_multipart(user).headers(
      "Content-Type": "multipart/form-data; boundary=boundary123"
    ).exec(
      Api::Shards::Upload,
      body: io.to_s
    )

    response.should send_json(201)

    shard = ShardQuery.new.name("minimal-multipart-shard").first?
    shard.should_not be_nil
    shard.try(&.description).should be_nil
    shard.try(&.homepage_url).should be_nil
  end

  pending "creates shard version with correct checksum" do
    package_content = "versioned package content"
    checksum = Digest::SHA256.hexdigest(package_content)
    user = UserFactory.create

    io = IO::Memory.new
    builder = HTTP::FormData::Builder.new(io, "boundary123")

    builder.field("name", "versioned-shard")
    builder.field("version", "2.5.3")
    builder.field("repository_url", "https://github.com/user/versioned-shard")

    builder.file(
      "package",
      IO::Memory.new(package_content),
      HTTP::FormData::FileMetadata.new(filename: "package.tar.gz")
    )

    builder.finish

    response = ApiClient.auth_multipart(user).headers(
      "Content-Type": "multipart/form-data; boundary=boundary123"
    ).exec(
      Api::Shards::Upload,
      body: io.to_s
    )

    response.should send_json(201)
    json = JSON.parse(response.body)
    version_id = json["version"]["id"].as_i64

    # Verify shard version was created with checksum
    version = ShardVersionQuery.new.id(version_id).first?
    version.should_not be_nil
    version.try(&.version).should eq("2.5.3")
    version.try(&.checksum).should eq(checksum)
  end

  pending "prevents duplicate version uploads" do
    package_content = "first upload content"

    user = UserFactory.create
    # First upload
    io = IO::Memory.new
    builder = HTTP::FormData::Builder.new(io, "boundary123")
    builder.field("name", "duplicate-test-shard")
    builder.field("version", "1.0.0")
    builder.field("repository_url", "https://github.com/user/duplicate-test-shard")
    builder.file(
      "package",
      IO::Memory.new(package_content),
      HTTP::FormData::FileMetadata.new(filename: "package.tar.gz")
    )
    builder.finish

    response = ApiClient.auth_multipart(user).headers(
      "Content-Type": "multipart/form-data; boundary=boundary123"
    ).exec(
      Api::Shards::Upload,
      body: io.to_s
    )
    response.should send_json(201)

    # Attempt duplicate upload with different content
    different_content = "second upload content"
    io2 = IO::Memory.new
    builder2 = HTTP::FormData::Builder.new(io2, "boundary456")
    builder2.field("name", "duplicate-test-shard")
    builder2.field("version", "1.0.0")
    builder2.field("repository_url", "https://github.com/user/duplicate-test-shard")
    builder2.file(
      "package",
      IO::Memory.new(different_content),
      HTTP::FormData::FileMetadata.new(filename: "package.tar.gz")
    )
    builder2.finish

    response2 = ApiClient.auth(user).exec(
      Api::Shards::Upload,
      headers: HTTP::Headers{"Content-Type" => "multipart/form-data; boundary=boundary456"},
      body: io2.to_s
    )
    response2.should send_json(422)
    response2.body.should contain("errors")
  end

  pending "rejects packages exceeding size limit" do
    # Create a package content larger than 50 MB
    large_content = "x" * (51 * 1024 * 1024)
    user = UserFactory.create

    io = IO::Memory.new
    builder = HTTP::FormData::Builder.new(io, "boundary123")
    builder.field("name", "large-package-shard")
    builder.field("version", "1.0.0")
    builder.field("repository_url", "https://github.com/user/large-package-shard")
    builder.file(
      "package",
      IO::Memory.new(large_content),
      HTTP::FormData::FileMetadata.new(filename: "package.tar.gz")
    )
    builder.finish

    response = ApiClient.auth_multipart(user).headers(
      "Content-Type": "multipart/form-data; boundary=boundary123"
    ).exec(
      Api::Shards::Upload,
      body: io.to_s
    )

    response.should send_json(413)
    json = JSON.parse(response.body)
    json["error"].should eq("Package size exceeds maximum allowed size")
    json["max_size_mb"].should eq(50)
  end

  it "requires authentication" do
    package_content = "test content"

    io = IO::Memory.new
    builder = HTTP::FormData::Builder.new(io, "boundary123")
    builder.field("name", "auth-test-shard")
    builder.field("version", "1.0.0")
    builder.field("repository_url", "https://github.com/user/auth-test-shard")
    builder.file(
      "package",
      IO::Memory.new(package_content),
      HTTP::FormData::FileMetadata.new(filename: "package.tar.gz")
    )
    builder.finish

    response = ApiClient.exec(
      Api::Shards::Upload,
      headers: HTTP::Headers{"Content-Type" => "multipart/form-data; boundary=boundary123"},
      body: io.to_s
    )

    response.status_code.should eq(401)
  end

  pending "enqueues IndexShardWorker after successful upload" do
    package_content = "worker test content"
    checksum = Digest::SHA256.hexdigest(package_content)
    user = UserFactory.create

    io = IO::Memory.new
    builder = HTTP::FormData::Builder.new(io, "boundary123")

    builder.field("name", "worker-test-shard")
    builder.field("version", "1.2.3")
    builder.field("repository_url", "https://github.com/user/worker-test-shard")

    builder.file(
      "package",
      IO::Memory.new(package_content),
      HTTP::FormData::FileMetadata.new(filename: "package.tar.gz")
    )

    builder.finish

    # Mock or capture worker enqueue calls if testing framework supports it
    # For now, verify the request succeeds (worker enqueue is gracefully handled in tests)
    response = ApiClient.auth_multipart(user).headers(
      "Content-Type": "multipart/form-data; boundary=boundary123"
    ).exec(
      Api::Shards::Upload,
      body: io.to_s
    )

    response.should send_json(201)
    json = JSON.parse(response.body)
    json["message"].should eq("Shard uploaded successfully")

    # Verify shard and version were created
    shard = ShardQuery.new.name("worker-test-shard").first?
    shard.should_not be_nil
    version = ShardVersionQuery.new.shard_id(shard.not_nil!.id).version("1.2.3").first?
    version.should_not be_nil
    version.not_nil!.checksum.should eq(checksum)

    # Note: In production, IndexShardWorker.enqueue would be called here
    # Worker execution is tested separately in worker specs
  end
end
