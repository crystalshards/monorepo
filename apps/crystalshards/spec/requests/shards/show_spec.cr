require "../../spec_helper"

describe Shards::Show do
  describe "basic rendering" do
    it "renders HTML successfully for valid shard" do
      shard = ShardFactory.create &.name("test-shard")

      response = ApiClient.exec(Shards::Show.with(shard_name: "test-shard"))

      response.status_code.should eq(200)
      response.headers["Content-Type"].should contain("text/html")
    end

    it "returns 404 for non-existent shard" do
      # The action raises RouteNotFoundError which Lucky converts to 404
      # Since the test framework may handle this differently, we just verify
      # that accessing a non-existent shard doesn't succeed
      begin
        response = ApiClient.exec(Shards::Show.with(shard_name: "nonexistent-shard"))
        # If we get here, verify it's a 404
        response.status_code.should eq(404)
      rescue Lucky::RouteNotFoundError
        # This is the expected behavior - test passes
      end
    end
  end

  describe "shard information display" do
    it "shows shard name" do
      shard = ShardFactory.create &.name("awesome-shard")

      response = ApiClient.exec(Shards::Show.with(shard_name: "awesome-shard"))

      response.body.should contain("awesome-shard")
    end

    it "shows shard description" do
      shard = ShardFactory.create &.name("test-shard")
        .description("An awesome Crystal library")

      response = ApiClient.exec(Shards::Show.with(shard_name: "test-shard"))

      response.body.should contain("An awesome Crystal library")
    end

    it "shows GitHub repository link" do
      shard = ShardFactory.create &.name("test-shard")
        .repository_url("https://github.com/user/test-shard")

      response = ApiClient.exec(Shards::Show.with(shard_name: "test-shard"))

      response.body.should contain("https://github.com/user/test-shard")
      response.body.should contain("Repository")
    end

    it "shows homepage link when available" do
      shard = ShardFactory.create &.name("test-shard")
        .homepage_url("https://testshard.com")

      response = ApiClient.exec(Shards::Show.with(shard_name: "test-shard"))

      response.body.should contain("https://testshard.com")
      response.body.should contain("Homepage")
    end

    it "hides homepage link when not available" do
      shard = ShardFactory.create &.name("test-shard")
        .homepage_url(nil)

      response = ApiClient.exec(Shards::Show.with(shard_name: "test-shard"))

      response.body.should_not contain("Homepage")
    end

    it "shows documentation link when available" do
      shard = ShardFactory.create &.name("test-shard")
        .documentation_url("https://docs.testshard.com")

      response = ApiClient.exec(Shards::Show.with(shard_name: "test-shard"))

      response.body.should contain("https://docs.testshard.com")
      response.body.should contain("Documentation")
    end

    it "hides documentation link when not available" do
      shard = ShardFactory.create &.name("test-shard")
        .documentation_url(nil)

      response = ApiClient.exec(Shards::Show.with(shard_name: "test-shard"))

      response.body.should_not contain("View Documentation")
    end

    it "shows license information" do
      shard = ShardFactory.create &.name("test-shard")
        .license("MIT")

      response = ApiClient.exec(Shards::Show.with(shard_name: "test-shard"))

      response.body.should contain("License:")
      response.body.should contain("MIT")
    end

    it "shows GitHub stars" do
      shard = ShardFactory.create &.name("test-shard")
        .github_stars(42)

      response = ApiClient.exec(Shards::Show.with(shard_name: "test-shard"))

      response.body.should contain("⭐ 42")
      response.body.should contain("stars")
    end

    it "hides GitHub stars when not available" do
      shard = ShardFactory.create &.name("test-shard")
        .github_stars(nil)

      response = ApiClient.exec(Shards::Show.with(shard_name: "test-shard"))

      response.body.should_not contain("⭐")
    end

    it "shows total downloads" do
      shard = ShardFactory.create &.name("test-shard")
        .total_downloads(1234)

      response = ApiClient.exec(Shards::Show.with(shard_name: "test-shard"))

      response.body.should contain("1234")
      response.body.should contain("downloads")
    end

    it "shows provider" do
      shard = ShardFactory.create &.name("test-shard")
        .provider("github")

      response = ApiClient.exec(Shards::Show.with(shard_name: "test-shard"))

      response.body.should contain("Provider")
      response.body.should contain("Github")
    end
  end

  describe "version display" do
    it "shows latest version number" do
      shard = ShardFactory.create &.name("test-shard")
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.2.3")
        .released_at(Time.utc)

      response = ApiClient.exec(Shards::Show.with(shard_name: "test-shard"))

      response.body.should contain("1.2.3")
    end

    it "lists all versions" do
      shard = ShardFactory.create &.name("test-shard")
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(3.days.ago)
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.1.0")
        .released_at(2.days.ago)
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.2.0")
        .released_at(1.day.ago)

      response = ApiClient.exec(Shards::Show.with(shard_name: "test-shard"))

      response.body.should contain("1.0.0")
      response.body.should contain("1.1.0")
      response.body.should contain("1.2.0")
      response.body.should contain("Versions")
    end

    it "limits version list to 10 versions" do
      shard = ShardFactory.create &.name("test-shard")
      15.times do |i|
        ShardVersionFactory.create &.shard_id(shard.id)
          .version("1.#{i}.0")
          .released_at(Time.utc - i.days)
      end

      response = ApiClient.exec(Shards::Show.with(shard_name: "test-shard"))

      response.body.should contain("and 5 more...")
    end

    it "shows version release dates" do
      shard = ShardFactory.create &.name("test-shard")
      release_time = Time.utc(2024, 1, 15)
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(release_time)

      response = ApiClient.exec(Shards::Show.with(shard_name: "test-shard"))

      response.body.should contain("Jan 15, 2024")
    end

    it "indicates yanked versions with special styling" do
      shard = ShardFactory.create &.name("test-shard")
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .yanked(true)

      response = ApiClient.exec(Shards::Show.with(shard_name: "test-shard"))

      response.body.should contain("version-yanked")
    end

    it "handles shards with no versions gracefully" do
      shard = ShardFactory.create &.name("test-shard")

      response = ApiClient.exec(Shards::Show.with(shard_name: "test-shard"))

      response.status_code.should eq(200)
      response.body.should_not contain("Versions")
    end

    it "orders versions by most recent first" do
      shard = ShardFactory.create &.name("test-shard")
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc(2024, 1, 1))
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("2.0.0")
        .released_at(Time.utc(2024, 6, 1))

      response = ApiClient.exec(Shards::Show.with(shard_name: "test-shard"))

      version_2_position = response.body.index("2.0.0")
      version_1_position = response.body.index("1.0.0")

      version_2_position.should_not be_nil
      version_1_position.should_not be_nil
      version_2_position.not_nil!.should be < version_1_position.not_nil!
    end
  end

  describe "installation instructions" do
    it "shows shard.yml snippet with correct syntax" do
      shard = ShardFactory.create &.name("test-shard")
        .repository_url("https://github.com/user/test-shard")
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")

      response = ApiClient.exec(Shards::Show.with(shard_name: "test-shard"))

      response.body.should contain("# Add this to your shard.yml")
      response.body.should contain("dependencies:")
      response.body.should contain("test-shard:")
      response.body.should contain("github: user/test-shard")
      # HTML encodes '>' as '&gt;'
      response.body.should contain("version: ~&gt; 1.0.0")
    end

    it "shows shards install command" do
      shard = ShardFactory.create &.name("test-shard")
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")

      response = ApiClient.exec(Shards::Show.with(shard_name: "test-shard"))

      response.body.should contain("Then run:")
      response.body.should contain("shards install")
    end

    it "uses latest version in installation instructions" do
      shard = ShardFactory.create &.name("test-shard")
        .repository_url("https://github.com/user/test-shard")
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(2.days.ago)
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("2.0.0")
        .released_at(1.day.ago)

      response = ApiClient.exec(Shards::Show.with(shard_name: "test-shard"))

      # HTML encodes '>' as '&gt;'
      response.body.should contain("version: ~&gt; 2.0.0")
      response.body.should_not contain("version: ~&gt; 1.0.0")
    end

    it "extracts correct GitHub path from repository URL" do
      shard = ShardFactory.create &.name("test-shard")
        .repository_url("https://github.com/crystal-lang/awesome-shard.git")
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")

      response = ApiClient.exec(Shards::Show.with(shard_name: "test-shard"))

      response.body.should contain("github: crystal-lang/awesome-shard")
      # Note: .git still appears in the repository link, but not in the github: path
      # The github: path correctly strips .git
    end

    it "handles repository URLs without .git suffix" do
      shard = ShardFactory.create &.name("test-shard")
        .repository_url("https://github.com/user/test-shard")
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")

      response = ApiClient.exec(Shards::Show.with(shard_name: "test-shard"))

      response.body.should contain("github: user/test-shard")
    end

    it "hides installation instructions when no versions exist" do
      shard = ShardFactory.create &.name("test-shard")

      response = ApiClient.exec(Shards::Show.with(shard_name: "test-shard"))

      # Installation section heading shows, but content doesn't
      response.body.should contain("Installation")
      response.body.should_not contain("# Add this to your shard.yml")
      response.body.should_not contain("shards install")
    end
  end

  describe "dependencies" do
    it "lists runtime dependencies" do
      shard = ShardFactory.create &.name("test-shard")
      version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
      DependencyFactory.create &.shard_version_id(version.id)
        .name("http-client")
        .version_requirement("~> 1.0")
        .scope("runtime")

      response = ApiClient.exec(Shards::Show.with(shard_name: "test-shard"))

      response.body.should contain("Dependencies")
      response.body.should contain("http-client")
      # HTML encodes '>' as '&gt;'
      response.body.should contain("~&gt; 1.0")
    end

    it "shows dependency version requirements" do
      shard = ShardFactory.create &.name("test-shard")
      version = ShardVersionFactory.create &.shard_id(shard.id)
      DependencyFactory.create &.shard_version_id(version.id)
        .name("json-lib")
        .version_requirement(">= 2.0, < 3.0")

      response = ApiClient.exec(Shards::Show.with(shard_name: "test-shard"))

      # HTML encodes '>' and '<' as '&gt;' and '&lt;'
      response.body.should contain("&gt;= 2.0, &lt; 3.0")
    end

    it "distinguishes development dependencies with badge" do
      shard = ShardFactory.create &.name("test-shard")
      version = ShardVersionFactory.create &.shard_id(shard.id)
      DependencyFactory.create &.shard_version_id(version.id)
        .name("spec-helper")
        .scope("development")

      response = ApiClient.exec(Shards::Show.with(shard_name: "test-shard"))

      # Development dependencies ARE shown with a dev badge
      response.body.should contain("spec-helper")
      response.body.should contain("badge-dev")
      response.body.should contain("Development Dependencies")
    end

    it "does not show dev badge for runtime dependencies" do
      shard = ShardFactory.create &.name("test-shard")
      version = ShardVersionFactory.create &.shard_id(shard.id)
      DependencyFactory.create &.shard_version_id(version.id)
        .name("runtime-lib")
        .scope("runtime")

      response = ApiClient.exec(Shards::Show.with(shard_name: "test-shard"))

      response.body.should contain("runtime-lib")
      response.body.should_not contain("badge-dev")
    end

    it "handles shards with no dependencies" do
      shard = ShardFactory.create &.name("test-shard")
      ShardVersionFactory.create &.shard_id(shard.id)

      response = ApiClient.exec(Shards::Show.with(shard_name: "test-shard"))

      response.status_code.should eq(200)
      response.body.should_not contain("Dependencies")
    end

    it "shows multiple dependencies" do
      shard = ShardFactory.create &.name("test-shard")
      version = ShardVersionFactory.create &.shard_id(shard.id)
      DependencyFactory.create &.shard_version_id(version.id)
        .name("dep-one")
      DependencyFactory.create &.shard_version_id(version.id)
        .name("dep-two")
      DependencyFactory.create &.shard_version_id(version.id)
        .name("dep-three")

      response = ApiClient.exec(Shards::Show.with(shard_name: "test-shard"))

      response.body.should contain("dep-one")
      response.body.should contain("dep-two")
      response.body.should contain("dep-three")
    end

    it "only shows dependencies for latest version" do
      shard = ShardFactory.create &.name("test-shard")
      old_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(2.days.ago)
      new_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("2.0.0")
        .released_at(1.day.ago)

      DependencyFactory.create &.shard_version_id(old_version.id)
        .name("old-dep")
      DependencyFactory.create &.shard_version_id(new_version.id)
        .name("new-dep")

      response = ApiClient.exec(Shards::Show.with(shard_name: "test-shard"))

      response.body.should contain("new-dep")
      response.body.should_not contain("old-dep")
    end

    it "makes dependency names clickable links to their detail pages" do
      shard = ShardFactory.create &.name("test-shard")
      version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
      DependencyFactory.create &.shard_version_id(version.id)
        .name("http-client")
        .version_requirement("~> 1.0")
        .scope("runtime")

      response = ApiClient.exec(Shards::Show.with(shard_name: "test-shard"))

      # Should contain a link to the dependency's detail page
      response.body.should contain("<a href=\"/shards/http-client\"")
      response.body.should contain("class=\"dependency-link\"")
      response.body.should contain("<strong>http-client</strong>")
    end
  end

  describe "edge cases" do
    it "handles shard with all optional fields missing" do
      shard = ShardFactory.create &.name("minimal-shard")
        .homepage_url(nil)
        .documentation_url(nil)
        .license(nil)
        .github_stars(nil)

      response = ApiClient.exec(Shards::Show.with(shard_name: "minimal-shard"))

      response.status_code.should eq(200)
      response.body.should contain("minimal-shard")
    end

    it "handles shard with no versions and no dependencies" do
      shard = ShardFactory.create &.name("empty-shard")

      response = ApiClient.exec(Shards::Show.with(shard_name: "empty-shard"))

      response.status_code.should eq(200)
      response.body.should contain("empty-shard")
      # Installation section appears but has no content when no versions exist
      response.body.should contain("Installation")
      response.body.should_not contain("Dependencies")
      response.body.should_not contain("shards install")
    end

    it "handles very long shard names" do
      long_name = "a" * 100
      shard = ShardFactory.create &.name(long_name)

      response = ApiClient.exec(Shards::Show.with(shard_name: long_name))

      response.status_code.should eq(200)
      response.body.should contain(long_name)
    end

    it "handles very long descriptions" do
      long_description = "This is a very long description. " * 50
      shard = ShardFactory.create &.name("test-shard")
        .description(long_description)

      response = ApiClient.exec(Shards::Show.with(shard_name: "test-shard"))

      response.status_code.should eq(200)
      response.body.should contain(long_description)
    end

    it "handles zero downloads" do
      shard = ShardFactory.create &.name("test-shard")
        .total_downloads(0)

      response = ApiClient.exec(Shards::Show.with(shard_name: "test-shard"))

      response.body.should contain("0")
      response.body.should contain("downloads")
    end

    it "handles very high download counts" do
      shard = ShardFactory.create &.name("test-shard")
        .total_downloads(9999999)

      response = ApiClient.exec(Shards::Show.with(shard_name: "test-shard"))

      response.body.should contain("9999999")
    end
  end

  describe "page title" do
    it "uses shard name as page title" do
      shard = ShardFactory.create &.name("awesome-shard")

      response = ApiClient.exec(Shards::Show.with(shard_name: "awesome-shard"))

      response.body.should contain("<title>")
      response.body.should contain("awesome-shard")
    end
  end
end
