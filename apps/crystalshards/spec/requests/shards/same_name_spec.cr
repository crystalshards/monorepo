require "../../spec_helper"

# The case the old schema could not represent: one name, two repositories, two
# different hosts. Under the old unique-on-name constraint the second one could
# not be created at all, and there was only ever one /shards/router to serve.
describe "two shards sharing a name on different hosts" do
  it "lets both exist, with distinct identities and the same name" do
    github, gitlab = create_same_name_pair

    github.name.should eq("router")
    gitlab.name.should eq("router")
    github.canonical_slug.should eq("github.com/kemalcr/router")
    gitlab.canonical_slug.should eq("gitlab.com/acme/router")
    ShardQuery.new.name("router").select_count.should eq(2)
  end

  it "refuses a second shard for the same repository" do
    create_same_name_pair

    SaveShard.create(
      name: "router-again",
      repository_url: "https://github.com/kemalcr/router",
      provider: "github",
      repository_type: "git"
    ) do |operation, shard|
      shard.should be_nil
      operation.canonical_slug.errors.first.should contain("already registered")
    end
  end

  it "serves each at its own URL" do
    github, gitlab = create_same_name_pair

    github_response = BrowserClient.exec(Shards::Show.with(**identity_of(github)))
    gitlab_response = BrowserClient.exec(Shards::Show.with(**identity_of(gitlab)))

    github_response.status_code.should eq(200)
    github_response.body.should contain("The GitHub router")
    github_response.body.should contain("github.com/kemalcr/router")
    github_response.body.should_not contain("The GitLab router")

    gitlab_response.status_code.should eq(200)
    gitlab_response.body.should contain("The GitLab router")
    gitlab_response.body.should contain("gitlab.com/acme/router")
    gitlab_response.body.should_not contain("The GitHub router")
  end

  it "links each to its own repository on its own host" do
    github, gitlab = create_same_name_pair

    BrowserClient.exec(Shards::Show.with(**identity_of(github)))
      .body.should contain("https://github.com/kemalcr/router")
    BrowserClient.exec(Shards::Show.with(**identity_of(gitlab)))
      .body.should contain("https://gitlab.com/acme/router")
  end

  it "gives each the install stanza its own host understands" do
    github, gitlab = create_same_name_pair
    ShardVersionFactory.create &.shard_id(github.id).version("1.0.0")
    ShardVersionFactory.create &.shard_id(gitlab.id).version("2.0.0")

    BrowserClient.exec(Shards::Show.with(**identity_of(github)))
      .body.should contain("github: kemalcr/router")
    BrowserClient.exec(Shards::Show.with(**identity_of(gitlab)))
      .body.should contain("gitlab: acme/router")
  end

  it "resolves a lookup to the right one" do
    github, gitlab = create_same_name_pair

    ShardQuery.new.resolve("github.com/kemalcr/router").not_nil!.id.should eq(github.id)
    ShardQuery.new.resolve("gitlab.com/acme/router").not_nil!.id.should eq(gitlab.id)
  end

  it "shows both in search, neither shadowing the other" do
    github, gitlab = create_same_name_pair

    found = ShardQuery.new.search("router").to_a.map(&.id)

    found.should contain(github.id)
    found.should contain(gitlab.id)
    found.size.should eq(2)
  end

  it "lists both on the browse page, each linking to its own URL" do
    create_same_name_pair

    response = BrowserClient.exec(Shards::Index.with(query: "router"))

    response.status_code.should eq(200)
    response.body.should contain("/shards/github.com/kemalcr/router")
    response.body.should contain("/shards/gitlab.com/acme/router")
    response.body.should contain("The GitHub router")
    response.body.should contain("The GitLab router")
  end

  it "returns each one's own payload from the API" do
    github, gitlab = create_same_name_pair

    github_json = JSON.parse(ApiClient.exec(Api::Shards::Show.with(**identity_of(github))).body)
    gitlab_json = JSON.parse(ApiClient.exec(Api::Shards::Show.with(**identity_of(gitlab))).body)

    github_json["canonical_slug"].should eq("github.com/kemalcr/router")
    github_json["repository_url"].should eq("https://github.com/kemalcr/router")
    gitlab_json["canonical_slug"].should eq("gitlab.com/acme/router")
    gitlab_json["repository_url"].should eq("https://gitlab.com/acme/router")
  end

  it "keeps their versions apart" do
    github, gitlab = create_same_name_pair
    ShardVersionFactory.create &.shard_id(github.id).version("1.0.0")
    ShardVersionFactory.create &.shard_id(gitlab.id).version("2.0.0")

    github_json = JSON.parse(
      ApiClient.exec(Api::Shards::Versions::Index.with(**identity_of(github))).body
    )
    gitlab_json = JSON.parse(
      ApiClient.exec(Api::Shards::Versions::Index.with(**identity_of(gitlab))).body
    )

    github_json["versions"].as_a.map { |v| v["version"] }.should eq(["1.0.0"])
    gitlab_json["versions"].as_a.map { |v| v["version"] }.should eq(["2.0.0"])
  end

  it "credits a download to the repository it was requested for" do
    github, gitlab = create_same_name_pair
    github_version = ShardVersionFactory.create &.shard_id(github.id).version("1.0.0")
    ShardVersionFactory.create &.shard_id(gitlab.id).version("1.0.0")

    response = ApiClient.exec(Api::Shards::Versions::Downloads::Create.with(
      **identity_of(github),
      version_number: "1.0.0"
    ))

    response.status_code.should eq(200)
    DownloadQuery.new.shard_id(github.id).select_count.should eq(1)
    DownloadQuery.new.shard_id(gitlab.id).select_count.should eq(0)
    ShardQuery.new.id(github.id).first.total_downloads.should eq(1)
    ShardQuery.new.id(gitlab.id).first.total_downloads.should eq(0)
    github_version.id.should_not be_nil
  end

  describe "the old /shards/:name URL" do
    it "sends an unambiguous name to the shard's own URL" do
      only = ShardFactory.create &.name("solo-shard")
        .repository_url("https://github.com/someone/solo-shard")

      response = BrowserClient.exec(Shards::ShowByName.with(shard_name: "solo-shard"))

      response.status_code.should eq(301)
      response.headers["Location"].should eq("/shards/github.com/someone/solo-shard")
      only.canonical_slug.should eq("github.com/someone/solo-shard")
    end

    it "sends an ambiguous name to search rather than picking one" do
      create_same_name_pair

      response = BrowserClient.exec(Shards::ShowByName.with(shard_name: "router"))

      response.status_code.should eq(302)
      response.headers["Location"].should contain("query=router")
    end

    it "404s a name nothing answers to" do
      response = BrowserClient.exec(Shards::ShowByName.with(shard_name: "no-such-shard"))

      response.status_code.should eq(404)
    end

    it "redirects the API path for an unambiguous name" do
      ShardFactory.create &.name("api-solo")
        .repository_url("https://github.com/someone/api-solo")

      response = ApiClient.exec(Api::Shards::ShowByName.with(shard_name: "api-solo"))

      response.status_code.should eq(301)
      response.headers["Location"].should eq("/api/shards/github.com/someone/api-solo")
    end

    it "answers an ambiguous API name with the candidates, not a guess" do
      create_same_name_pair

      response = ApiClient.exec(Api::Shards::ShowByName.with(shard_name: "router"))

      response.status_code.should eq(409)
      candidates = JSON.parse(response.body)["candidates"].as_a.map(&.as_s)
      candidates.should contain("/shards/github.com/kemalcr/router")
      candidates.should contain("/shards/gitlab.com/acme/router")
    end
  end
end
