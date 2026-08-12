require "../../spec_helper"

# The states a shard page has to render.
#
# 217 shards were discovered by bisecting GitHub's code search on manifest byte
# size, ascending, which surfaced the smallest shard.yml files on the platform
# first. So the corpus is skewed hard toward trivial repositories, and no tags,
# no README, no description and no licence are the NORMAL cases here rather
# than the edges. Each one therefore gets an asserted rendering: a page that
# renders nothing for the common case is the bug these specs exist to stop.

# A manifest with everything in it, so the fully-indexed rendering has
# something to be right about.
def full_shard_manifest : JSON::Any
  JSON.parse(<<-JSON)
    {
      "name": "kemal",
      "version": "1.12.0",
      "description": "A Lightning Fast, Super Simple web framework",
      "crystal": ">= 1.0.0",
      "license": "MIT",
      "authors": ["Serdar Dogruyol"],
      "targets": { "kemal": { "main": "src/kemal.cr" } },
      "executables": ["kemal"],
      "dependencies": {
        "radix": { "github": "luislavena/radix", "version": "~> 0.4" },
        "exception_page": { "github": "crystal-loot/exception_page", "branch": "master" }
      },
      "development_dependencies": {
        "ameba": { "github": "crystal-ameba/ameba" }
      }
    }
    JSON
end

# A row the identity backfill could not parse: no host, no owner, no repo, no
# canonical slug, and a recorded reason. SaveShard cannot create one, by
# design, because every write from here on requires an identity, so this is
# inserted the way the backfill writes it.
def insert_unidentified_row(name : String, repository_url : String, reason : String) : Int64
  AppDatabase.query_one(
    <<-SQL,
    INSERT INTO shards
      (name, repository_url, provider, repository_type, total_downloads,
       identity_error, created_at, updated_at)
    VALUES ($1, $2, 'github', 'git', 0, $3, NOW(), NOW())
    RETURNING id
    SQL
    name, repository_url, reason, as: Int64
  )
end

describe Shards::Show do
  describe "a fully indexed shard" do
    it "renders the identity, the signals, the manifest, the deps and the README" do
      radix = ShardFactory.create &.name("radix").at("github.com", "luislavena", "radix")

      shard = ShardFactory.create &.name("kemal")
        .at("github.com", "kemalcr", "kemal")
        .description("A Lightning Fast, Super Simple web framework")
        .license("MIT")
        .github_stars(3903)
        .readme_content("# Kemal\n\nLightning fast web framework.")
        .last_synced_at(Time.utc(2026, 8, 1))

      version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.12.0")
        .released_at(Time.utc(2026, 7, 4))
        .commit_sha("abcdef1234567890")
        .crystal_version(">= 1.0.0")
        .metadata(full_shard_manifest)

      DependencyFactory.create &.shard_version_id(version.id)
        .name("radix")
        .version_requirement("~> 0.4")
        .scope("runtime")
        .dependent_shard_id(radix.id)

      DependencyFactory.create &.shard_version_id(version.id)
        .name("ameba")
        .version_requirement("*")
        .scope("development")

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))
      body = response.body

      response.status_code.should eq(200)

      # Identity: which repository this is, not just what it calls itself.
      body.should contain("kemal")
      body.should contain("github.com/kemalcr/kemal")

      # Popularity: stars and dependents, and no download figure anywhere.
      body.should contain("3903")
      body.should contain("stars")
      body.should contain("dependents")
      body.should_not contain("downloads")

      body.should contain("MIT")

      # The parsed manifest, every field the brief names.
      body.should contain("&gt;= 1.0.0")
      body.should contain("Serdar Dogruyol")
      body.should contain("<dt>Target</dt>")
      body.should contain("src/kemal.cr")
      body.should contain("<dt>Executable</dt>")

      # Dependencies, with the resolved one linked and the unresolved one not.
      body.should contain("Runtime Dependencies")
      body.should contain("/shards/github.com/luislavena/radix")
      body.should contain("Development Dependencies")
      body.should contain("ameba")
      body.should contain("badge-dev")

      # The source shorthand, which is the half the Dependency row cannot hold.
      body.should contain("github: luislavena/radix")

      # The tag itself.
      body.should contain("1.12.0")
      body.should contain("Jul 4, 2026")
      body.should contain("abcdef123456")

      body.should contain("Lightning fast web framework.")
    end

    it "reports a shard.yml that declares nothing beyond a name" do
      shard = ShardFactory.create &.name("tiny").at("github.com", "someone", "tiny")
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("0.1.0")
        .metadata(JSON.parse(%({"name": "tiny", "version": "0.1.0"})))

      body = BrowserClient.exec(Shards::Show.with(**identity_of(shard))).body

      body.should contain("declares only a name and a version")
      body.should contain("plain library with nothing to build")
    end
  end

  describe "a shard with no tags" do
    it "says so, and offers the snippet that actually works for it" do
      shard = ShardFactory.create &.name("untagged")
        .at("github.com", "someone", "untagged")

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))
      body = response.body

      response.status_code.should eq(200)
      body.should contain("No tagged releases")
      body.should contain("resolves a version from a git tag")
      body.should contain("github: someone/untagged")
      body.should contain("No release to pin to")
      # No version, so nothing claims to know this repository's dependencies.
      body.should_not contain("<h2>Dependencies</h2>")
    end

    # A repository with no tags is recorded by tracking its default branch, and
    # that branch name lands in the version column. Calling it a release, or
    # writing `version: ~> master`, would be wrong in two different ways.
    it "renders a tracked branch as a branch, not as a release" do
      shard = ShardFactory.create &.name("branchy")
        .at("github.com", "someone", "branchy")
      # source is what the indexer records, and what release? now reads. Before
      # the indexer landed this was inferred from the shape of the version
      # string, which could not tell a branch called "v2" from the tag.
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("master")
        .source(ShardVersion::Source::BRANCH)
        .metadata(JSON.parse(%({"name": "branchy"})))

      body = BrowserClient.exec(Shards::Show.with(**identity_of(shard))).body

      body.should contain("master branch")
      body.should contain("This branch")
      body.should contain("branch: master")
      body.should contain("is a branch, not a release")
      body.should_not contain("version: ~&gt; master")
    end
  end

  describe "a shard with no README" do
    it "says the README is not indexed and links where it can be read" do
      shard = ShardFactory.create &.name("bare")
        .at("github.com", "someone", "bare")
        .readme_content(nil)
      ShardVersionFactory.create &.shard_id(shard.id).version("1.0.0")

      response = BrowserClient.exec(Shards::Show.with(**identity_of(shard)))
      body = response.body

      response.status_code.should eq(200)
      body.should contain("README")
      body.should contain("No README has been indexed for this shard yet.")
      body.should contain("https://github.com/someone/bare")
    end
  end

  describe "a shard whose index failed" do
    # The real shape of a failed index: no host, no owner, no repo, no slug,
    # and a reason. Such a row has no canonical URL, so its only address is the
    # legacy name route, and the page has to render there too.
    it "states why nothing was indexed when the repository could not be identified" do
      insert_unidentified_row(
        "mystery",
        "https://github.com/just-an-owner",
        "is not a repository URL: no repository segment"
      )

      response = BrowserClient.exec(Shards::ShowByName.with(shard_name: "mystery"))
      body = response.body

      response.status_code.should eq(200)
      body.should contain("could not be identified")
      body.should contain("is not a repository URL: no repository segment")
      body.should contain("Not indexed:")
    end

    # A row with no identity has no versioned URL to offer, so the picker names
    # its versions without linking them anywhere. A link would 404, which is
    # the exact failure this work exists to remove.
    it "names an unidentified row's versions without linking them" do
      id = insert_unidentified_row(
        "orphan",
        "https://github.com/just-an-owner",
        "is not a repository URL: no repository segment"
      )
      ShardVersionFactory.create &.shard_id(id)
        .version("1.0.0").released_at(Time.utc(2024, 1, 1))
      ShardVersionFactory.create &.shard_id(id)
        .version("2.0.0").released_at(Time.utc(2025, 1, 1))

      body = BrowserClient.exec(Shards::ShowByName.with(shard_name: "orphan")).body

      body.should contain("1.0.0")
      body.should contain("2.0.0")
      body.should contain("version-picker-option-static")
      body.should_not contain("/versions/1.0.0")
    end

    it "states that the repository could not be reached" do
      shard = ShardFactory.create &.name("gone").at("github.com", "someone", "gone")
      SaveShard.update!(shard, unavailable_at: Time.utc)

      body = BrowserClient.exec(Shards::Show.with(**identity_of(shard))).body

      body.should contain("could not reach this repository")
      body.should contain("repositories come back")
    end

    it "says a version is recorded but unread rather than drawing an empty manifest" do
      shard = ShardFactory.create &.name("pending").at("github.com", "someone", "pending")
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("2.0.0")
        .metadata(nil)

      body = BrowserClient.exec(Shards::Show.with(**identity_of(shard))).body

      body.should contain("Nothing has been indexed for 2.0.0 yet.")
      body.should contain("No shard.yml has been indexed for 2.0.0")
      body.should contain("has not been read yet")
      body.should contain("badge-unindexed")
      body.should contain("not yet")
    end

    it "reports never having synced rather than showing a blank date" do
      shard = ShardFactory.create &.name("never").at("github.com", "someone", "never")
        .last_synced_at(nil)

      body = BrowserClient.exec(Shards::Show.with(**identity_of(shard))).body

      body.should contain("Synced")
      body.should contain("never")
    end
  end
end

describe Shards::Versions::Show do
  describe "switching to an older version" do
    it "renders the selected version's manifest, dependencies and tag date" do
      shard = ShardFactory.create &.name("switcher")
        .at("github.com", "someone", "switcher")

      old = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc(2024, 1, 15))
        .crystal_version(">= 0.35.0")
        .metadata(JSON.parse(%({"name": "switcher", "crystal": ">= 0.35.0"})))

      recent = ShardVersionFactory.create &.shard_id(shard.id)
        .version("2.0.0")
        .released_at(Time.utc(2026, 6, 1))
        .crystal_version(">= 1.0.0")
        .metadata(JSON.parse(%({"name": "switcher", "crystal": ">= 1.0.0"})))

      DependencyFactory.create &.shard_version_id(old.id)
        .name("old-only-dep")
        .version_requirement("~> 0.1")
      DependencyFactory.create &.shard_version_id(recent.id)
        .name("new-only-dep")
        .version_requirement("~> 2.0")

      response = BrowserClient.exec(
        Shards::Versions::Show.with(**identity_of(shard), version: "1.0.0")
      )
      body = response.body

      response.status_code.should eq(200)

      # The selected version, its constraint, its tag date and its deps.
      body.should contain("&gt;= 0.35.0")
      body.should contain("Jan 15, 2024")
      body.should contain("old-only-dep")
      body.should contain("version: ~&gt; 1.0.0")

      # Not the latest one's.
      body.should_not contain("new-only-dep")
      body.should_not contain("&gt;= 1.0.0")
      body.should_not contain("version: ~&gt; 2.0.0")
    end

    it "marks the selected version current and keeps the newest addressable" do
      shard = ShardFactory.create &.name("current")
        .at("github.com", "someone", "current")
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0").released_at(Time.utc(2024, 1, 1))
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("2.0.0").released_at(Time.utc(2025, 1, 1))

      body = BrowserClient.exec(
        Shards::Versions::Show.with(**identity_of(shard), version: "1.0.0")
      ).body

      body.should contain("aria-current=\"true\"")
      # The newest release links to the shard's canonical URL, not to a second
      # address for the same page.
      body.should contain("href=\"/shards/github.com/someone/current\"")
      body.should contain("version-picker-current\">1.0.0")
    end

    it "links every other version at its own versioned URL" do
      shard = ShardFactory.create &.name("linked").at("github.com", "someone", "linked")
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0").released_at(Time.utc(2024, 1, 1))
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.1.0").released_at(Time.utc(2024, 6, 1))
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("2.0.0").released_at(Time.utc(2025, 1, 1))

      body = BrowserClient.exec(Shards::Show.with(**identity_of(shard))).body

      body.should contain("/shards/github.com/someone/linked/versions/1.0.0")
      body.should contain("/shards/github.com/someone/linked/versions/1.1.0")
      # The latest keeps the canonical URL rather than a versioned duplicate.
      body.should_not contain("/shards/github.com/someone/linked/versions/2.0.0")
    end

    it "warns that the README belongs to the latest ref, not to an older tag" do
      shard = ShardFactory.create &.name("readme-drift")
        .at("github.com", "someone", "readme-drift")
        .readme_content("# Latest docs")
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0").released_at(Time.utc(2024, 1, 1))
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("2.0.0").released_at(Time.utc(2025, 1, 1))

      older = BrowserClient.exec(
        Shards::Versions::Show.with(**identity_of(shard), version: "1.0.0")
      ).body
      latest = BrowserClient.exec(Shards::Show.with(**identity_of(shard))).body

      older.should contain("not from the tag for this version")
      latest.should_not contain("not from the tag for this version")
    end

    # A URL naming a release that does not exist is the wrong page, not a
    # sparse one, and the whole point of this work is that a URL either has
    # content behind it or says outright that it does not.
    it "404s on a version this shard never published" do
      shard = ShardFactory.create &.name("nope").at("github.com", "someone", "nope")
      ShardVersionFactory.create &.shard_id(shard.id).version("1.0.0")

      begin
        response = BrowserClient.exec(
          Shards::Versions::Show.with(**identity_of(shard), version: "9.9.9")
        )
        response.status_code.should eq(404)
      rescue Lucky::RouteNotFoundError
        # Lucky turns this into a 404 in the error handler.
      end
    end

    it "404s on a versioned URL for a shard that does not exist" do
      begin
        response = BrowserClient.exec(
          Shards::Versions::Show.with(**unregistered_identity, version: "1.0.0")
        )
        response.status_code.should eq(404)
      rescue Lucky::RouteNotFoundError
      end
    end

    it "titles the page with the version being shown" do
      shard = ShardFactory.create &.name("titled").at("github.com", "someone", "titled")
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0").released_at(Time.utc(2024, 1, 1))
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("2.0.0").released_at(Time.utc(2025, 1, 1))

      body = BrowserClient.exec(
        Shards::Versions::Show.with(**identity_of(shard), version: "1.0.0")
      ).body

      body.should contain("<title>titled 1.0.0")
    end
  end
end
