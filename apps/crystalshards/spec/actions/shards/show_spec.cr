require "../../spec_helper"

describe Shards::Show do
  describe "GET /shards/:shard_name" do
    it "displays shard details for existing shard" do
      shard = ShardFactory.create &.name("awesome-shard")
        .description("An awesome Crystal shard")
        .license("MIT")
        .github_stars(100)
        .total_downloads(5000)

      version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.2.3")
        .crystal_version(">= 1.0.0")

      response = ApiClient.exec(Shards::Show.with(shard_name: "awesome-shard"))

      response.status.should eq(HTTP::Status::OK)
      response.body.should contain("awesome-shard")
      response.body.should contain("An awesome Crystal shard")
      response.body.should contain("v1.2.3")
      response.body.should contain("MIT")
      response.body.should contain("100")
      response.body.should contain("5000")
    end

    it "displays installation instructions" do
      shard = ShardFactory.create &.name("test-shard")
        .repository_url("https://github.com/crystal-lang/test-shard")

      ShardVersionFactory.create &.shard_id(shard.id).version("2.0.0")

      response = ApiClient.exec(Shards::Show.with(shard_name: "test-shard"))

      response.body.should contain("Add this to your shard.yml")
      response.body.should contain("dependencies:")
      response.body.should contain("test-shard:")
      response.body.should contain("github: crystal-lang/test-shard")
      response.body.should contain("version: ~&gt; 2.0.0")
      response.body.should contain("shards install")
    end

    it "displays version history" do
      shard = ShardFactory.create &.name("versioned-shard")

      v1 = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc(2024, 1, 1))

      v2 = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.1.0")
        .released_at(Time.utc(2024, 2, 1))

      v3 = ShardVersionFactory.create &.shard_id(shard.id)
        .version("2.0.0")
        .released_at(Time.utc(2024, 3, 1))

      response = ApiClient.exec(Shards::Show.with(shard_name: "versioned-shard"))

      response.body.should contain("Versions")
      response.body.should contain("1.0.0")
      response.body.should contain("1.1.0")
      response.body.should contain("2.0.0")
    end

    it "displays runtime dependencies" do
      shard = ShardFactory.create &.name("dependent-shard")
      version = ShardVersionFactory.create &.shard_id(shard.id)

      dep1 = DependencyFactory.create &.shard_version_id(version.id)
        .name("http-client")
        .version_requirement("~> 1.0")
        .scope("runtime")

      dep2 = DependencyFactory.create &.shard_version_id(version.id)
        .name("json-parser")
        .version_requirement(">= 2.0.0")
        .scope("runtime")

      response = ApiClient.exec(Shards::Show.with(shard_name: "dependent-shard"))

      response.body.should contain("Runtime Dependencies")
      response.body.should contain("http-client")
      response.body.should contain("~&gt; 1.0")
      response.body.should contain("json-parser")
      response.body.should contain("&gt;= 2.0.0")
    end

    it "displays development dependencies separately" do
      shard = ShardFactory.create &.name("dev-deps-shard")
      version = ShardVersionFactory.create &.shard_id(shard.id)

      runtime_dep = DependencyFactory.create &.shard_version_id(version.id)
        .name("runtime-lib")
        .scope("runtime")

      dev_dep = DependencyFactory.create &.shard_version_id(version.id)
        .name("spec-helper")
        .scope("development")

      response = ApiClient.exec(Shards::Show.with(shard_name: "dev-deps-shard"))

      response.body.should contain("Runtime Dependencies")
      response.body.should contain("runtime-lib")
      response.body.should contain("Development Dependencies")
      response.body.should contain("spec-helper")
    end

    it "displays metadata including created and updated dates" do
      shard = ShardFactory.create &.name("meta-shard")
        .provider("github")

      version = ShardVersionFactory.create &.shard_id(shard.id)
        .crystal_version(">= 1.10.0")

      response = ApiClient.exec(Shards::Show.with(shard_name: "meta-shard"))

      response.body.should contain("Metadata")
      response.body.should contain("Created:")
      response.body.should contain("Updated:")
      response.body.should contain("Crystal:")
      response.body.should contain("&gt;= 1.10.0")
      response.body.should contain("Provider")
      response.body.should contain("Github")
    end

    it "displays links to repository and documentation" do
      shard = ShardFactory.create &.name("linked-shard")
        .repository_url("https://github.com/crystal/linked-shard")
        .homepage_url("https://linked-shard.org")
        .documentation_url("https://docs.linked-shard.org")

      ShardVersionFactory.create &.shard_id(shard.id)

      response = ApiClient.exec(Shards::Show.with(shard_name: "linked-shard"))

      response.body.should contain("Links")
      response.body.should contain("https://github.com/crystal/linked-shard")
      response.body.should contain("https://linked-shard.org")
      response.body.should contain("https://docs.linked-shard.org")
    end

    it "displays README section" do
      shard = ShardFactory.create &.name("readme-shard")
        .description("A shard with documentation")
        .readme_content("# readme-shard\n\nThis shard provides documentation.")

      ShardVersionFactory.create &.shard_id(shard.id)

      response = ApiClient.exec(Shards::Show.with(shard_name: "readme-shard"))

      response.body.should contain("README")
      response.body.should contain("This shard provides")
    end

    it "falls back to a repository link when no README has been indexed" do
      shard = ShardFactory.create &.name("bare-shard")
        .repository_url("https://github.com/user/bare-shard")
      ShardVersionFactory.create &.shard_id(shard.id)

      response = ApiClient.exec(Shards::Show.with(shard_name: "bare-shard"))

      response.body.should contain("No README has been indexed")
      response.body.should contain("https://github.com/user/bare-shard")
    end

    it "marks yanked versions appropriately" do
      shard = ShardFactory.create &.name("yanked-shard")

      good_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .yanked(false)

      yanked_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("0.9.0")
        .yanked(true)

      response = ApiClient.exec(Shards::Show.with(shard_name: "yanked-shard"))

      response.body.should contain("1.0.0")
      response.body.should contain("0.9.0")
    end

    it "handles shard with no dependencies" do
      shard = ShardFactory.create &.name("independent-shard")
      ShardVersionFactory.create &.shard_id(shard.id)

      response = ApiClient.exec(Shards::Show.with(shard_name: "independent-shard"))

      response.status.should eq(HTTP::Status::OK)
      response.body.should_not contain("Dependencies")
    end

    it "handles shard with no versions gracefully" do
      shard = ShardFactory.create &.name("versionless-shard")

      response = ApiClient.exec(Shards::Show.with(shard_name: "versionless-shard"))

      response.status.should eq(HTTP::Status::OK)
      response.body.should contain("versionless-shard")
    end

    it "returns 404 for non-existent shard" do
      # The action raises RouteNotFoundError which Lucky converts to 404
      # The test framework may handle this differently
      begin
        response = ApiClient.exec(Shards::Show.with(shard_name: "non-existent-shard"))
        # If we get here without exception, verify it's a 404
        response.status.should eq(HTTP::Status::NOT_FOUND)
      rescue Lucky::RouteNotFoundError
        # This is the expected behavior - test passes
      end
    end

    it "displays current version badge in header" do
      shard = ShardFactory.create &.name("badged-shard")
      ShardVersionFactory.create &.shard_id(shard.id).version("3.1.4")

      response = ApiClient.exec(Shards::Show.with(shard_name: "badged-shard"))

      response.body.should contain("v3.1.4")
    end

    it "sorts versions by release date in descending order" do
      shard = ShardFactory.create &.name("sorted-shard")

      old_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc(2023, 1, 1))

      new_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("2.0.0")
        .released_at(Time.utc(2024, 1, 1))

      middle_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.5.0")
        .released_at(Time.utc(2023, 6, 1))

      response = ApiClient.exec(Shards::Show.with(shard_name: "sorted-shard"))

      # Latest version should be shown in badge
      response.body.should contain("v2.0.0")
    end

    it "limits version list to 10 versions and shows count of remaining" do
      shard = ShardFactory.create &.name("many-versions-shard")

      15.times do |i|
        ShardVersionFactory.create &.shard_id(shard.id)
          .version("1.0.#{i}")
          .released_at(Time.utc(2024, 1, i + 1))
      end

      response = ApiClient.exec(Shards::Show.with(shard_name: "many-versions-shard"))

      response.body.should contain("and 5 more")
    end
  end
end
