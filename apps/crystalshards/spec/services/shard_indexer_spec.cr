require "../spec_helper"

# Required directly, like the discovery specs: src/app.cr carries only
# version_order out of services/, because indexing runs in a Cloud Run Job
# rather than in the web server.
require "../../src/services/shard_indexer"

# Turning a discovered shard into a shard with content.
#
# No spec here reaches a host. Every one installs RecordedGithub behind
# RepositorySourceFactory.builder, which is the seam production resolves
# through, and RecordedGithub restores the previous builder in an `ensure`. The
# real GithubRepositoryApi runs underneath it, driven by a scripted requester,
# so URL shapes and status handling are exercised rather than stubbed past. A
# spec that reached an unscripted repo_path raises rather than falling through
# to the network.
private def indexable(
  owner : String = "kemalcr",
  repo : String = "kemal",
  host : String = "github.com",
) : Shard
  ShardFactory.create &.name(repo).at(host, owner, repo)
end

# A shard whose host column names a host the registry has no source for.
#
# SaveShard cannot create one: its URL gate admits exactly the four hosts
# RepositorySourceFactory reads, so a foreign repository_url is refused before
# an outcome could ever be recorded. What it does not check is that the host
# column agrees with the URL, so a row can carry a readable URL and an
# unreadable host. That is what a bad backfill or a hand-edited row looks like,
# and it is the only way this branch is reachable.
private def shard_hosted_on(host : String, owner : String, repo : String) : Shard
  shard = ShardFactory.create &.name(repo).at("github.com", owner, repo)

  AppDatabase.exec(
    "UPDATE shards SET host = $1, canonical_slug = $2 WHERE id = $3",
    host, "#{host}/#{owner}/#{repo}", shard.id
  )

  ShardQuery.new.id(shard.id).first
end

# A row from before identity existed: no host, no owner, no repo, no slug.
# SaveShard refuses to create one, which is exactly the situation these rows
# are left over from, so raw SQL is the only way to have one.
private def legacy_row(name : String, repository_url : String) : Shard
  id = AppDatabase.query_one(
    <<-SQL,
    INSERT INTO shards
      (name, repository_url, provider, repository_type, total_downloads,
       created_at, updated_at)
    VALUES ($1, $2, 'github', 'git', 0, NOW(), NOW())
    RETURNING id
    SQL
    name, repository_url, as: Int64
  )

  ShardQuery.new.id(id).first
end

private def kemal_manifest : String
  <<-YAML
  name: kemal
  version: 1.6.0
  crystal: ">= 1.12.0"
  license: MIT
  description: A Lightning Fast, Super Simple web framework
  dependencies:
    radix:
      github: luislavena/radix
  YAML
end

private def versions_of(shard : Shard) : Array(ShardVersion)
  ShardVersionQuery.new.shard_id(shard.id).to_a
end

private def version_of(shard : Shard, version : String) : ShardVersion
  ShardVersionQuery.new.shard_id(shard.id).version(version).first
end

private def reload(shard : Shard) : Shard
  ShardQuery.new.id(shard.id).first
end

describe ShardIndexer do
  describe "a shard that indexes" do
    it "stores the repository facts a page renders" do
      shard = indexable
      github = RecordedGithub.new("kemalcr/kemal")
        .repository(
          stars: 3903,
          forks: 630,
          description: "A Lightning Fast web framework",
          homepage: "https://kemalcr.com",
          license: "MIT",
          topics: ["crystal", "web"],
          default_branch: "master",
          pushed_at: Time.utc(2026, 2, 1),
          archived: false,
        )
        .tags("v1.6.0", "v1.5.0")
        .file("v1.6.0", "shard.yml", kemal_manifest)
        .file("v1.6.0", "README.md", "# Kemal\n\nUsage.")

      result = RecordedGithub.install(github) { ShardIndexer.index(shard) }

      result.outcome.should eq(ShardIndexer::Outcome::Indexed)
      result.versions.should eq(2)
      result.indexed_version.should eq("1.6.0")

      row = reload(shard)
      row.github_stars.should eq(3903)
      row.github_forks.should eq(630)
      row.topics.should eq(["crystal", "web"])
      row.default_branch.should eq("master")
      row.archived.should be_false
      row.readme_content.should eq("# Kemal\n\nUsage.")
      row.latest_version.should eq("1.6.0")
      row.indexed_at.should_not be_nil
      row.index_error.should be_nil
    end

    # The bug that cost 8 of 60 shards their whole pass on the first real run.
    #
    # A repository GitHub detects no licence for answers "license": null, not
    # an absent key. A JSON::Any wrapping null is truthy, so the try chain
    # walked into it and raised "Expected Hash for #[]?(key : String), not Nil"
    # out of fetch_snapshot, which the indexer records as a failed shard. The
    # fixture only ever omitted the key, so nothing produced the shape.
    it "indexes a repository whose licence is an explicit null" do
      shard = indexable
      github = RecordedGithub.new("kemalcr/kemal")
        .repository(null_license: true, default_branch: "master", stars: 12)
        .tags("v1.0.0")
        .file("v1.0.0", "shard.yml", "name: kemal\nversion: 1.0.0\n")

      result = RecordedGithub.install(github) { ShardIndexer.index(shard) }

      result.outcome.should eq(ShardIndexer::Outcome::Indexed)

      row = reload(shard)
      row.github_stars.should eq(12)
      # Not "null", not an empty string: the repository has no detected licence
      # and the row says nothing rather than saying something wrong.
      row.license.should be_nil
      row.index_error.should be_nil
    end

    it "writes a version row for every tag, not just the one it fetched" do
      shard = indexable
      github = RecordedGithub.new("kemalcr/kemal")
        .repository(default_branch: "master")
        .tags("v1.6.0", "v1.5.0", "v1.4.0")
        .file("v1.6.0", "shard.yml", kemal_manifest)

      RecordedGithub.install(github) { ShardIndexer.index(shard) }

      rows = versions_of(shard)
      rows.map(&.version).sort!.should eq(["1.4.0", "1.5.0", "1.6.0"])
      # Only the latest is fetched; the rest carry ref and sha and a nil
      # indexed_at, which is the signal a page uses to offer fetching an older
      # version on demand.
      rows.select(&.indexed?).map(&.version).should eq(["1.6.0"])
      rows.map(&.checkout_ref).sort!.should eq(["v1.4.0", "v1.5.0", "v1.6.0"])
      rows.all?(&.release?).should be_true
    end

    it "parses the latest version's manifest onto its row" do
      shard = indexable
      github = RecordedGithub.new("kemalcr/kemal")
        .tags("v1.6.0")
        .file("v1.6.0", "shard.yml", kemal_manifest)

      RecordedGithub.install(github) { ShardIndexer.index(shard) }

      version = version_of(shard, "1.6.0")
      version.crystal_version.should eq(">= 1.12.0")
      version.spec_yaml.should eq(kemal_manifest)
      version.spec_error.should be_nil
      version.metadata.not_nil!["dependencies"]["radix"]["github"].as_s
        .should eq("luislavena/radix")
    end

    it "prefers the manifest's own claims over the repository's" do
      # The repository's licence is GitHub reading a LICENSE file; the manifest
      # is the shard's own claim about itself, and it is the more specific one.
      shard = indexable
      github = RecordedGithub.new("kemalcr/kemal")
        .repository(description: "Detected by the host", license: "Apache-2.0")
        .tags("v1.6.0")
        .file("v1.6.0", "shard.yml", kemal_manifest)

      RecordedGithub.install(github) { ShardIndexer.index(shard) }

      row = reload(shard)
      row.license.should eq("MIT")
      row.description.should eq("A Lightning Fast, Super Simple web framework")
    end

    it "falls back to the repository's facts when the manifest says nothing" do
      shard = indexable
      github = RecordedGithub.new("kemalcr/kemal")
        .repository(description: "Detected by the host", license: "Apache-2.0")
        .tags("v1.6.0")
        .file("v1.6.0", "shard.yml", "name: kemal\n")

      RecordedGithub.install(github) { ShardIndexer.index(shard) }

      row = reload(shard)
      row.license.should eq("Apache-2.0")
      row.description.should eq("Detected by the host")
    end

    it "leaves a star count NULL rather than zero when the host did not say" do
      # A permanent 0 reads as "nobody uses this", which is a different and
      # wrong claim from "we have not looked".
      shard = indexable
      github = RecordedGithub.new("kemalcr/kemal").tags("v1.0.0")

      RecordedGithub.install(github) { ShardIndexer.index(shard) }

      row = reload(shard)
      row.github_stars.should be_nil
      row.github_forks.should be_nil
      # An empty topics array is a real answer, so it is stored rather than
      # left NULL: the repository declares none.
      row.topics.should eq([] of String)
    end

    it "dates one commit per shard rather than one per tag" do
      shard = indexable
      dated = Time.utc(2026, 3, 4)
      github = RecordedGithub.new("kemalcr/kemal")
        .repository(pushed_at: Time.utc(2026, 1, 1))
        .tags("v1.6.0", "v1.5.0", "v1.4.0")
        .file("v1.6.0", "shard.yml", kemal_manifest)
        .dated("v1.6.0", dated)

      RecordedGithub.install(github) { ShardIndexer.index(shard) }

      commit_requests = github.requested.count(&.includes?("/commits/"))
      commit_requests.should eq(1)

      version_of(shard, "1.6.0").released_at.to_unix.should eq(dated.to_unix)
      # The rest fall back to the repository's pushed_at, which is why nothing
      # downstream may order versions by date.
      version_of(shard, "1.4.0").released_at.to_unix
        .should eq(Time.utc(2026, 1, 1).to_unix)
    end

    it "tries the README spellings in turn and stops at the first that exists" do
      shard = indexable
      github = RecordedGithub.new("kemalcr/kemal")
        .tags("v1.0.0")
        .file("v1.0.0", "readme.md", "# lowercase")

      RecordedGithub.install(github) { ShardIndexer.index(shard) }

      reload(shard).readme_content.should eq("# lowercase")
      github.requested.count(&.includes?("README.markdown")).should eq(0)
    end

    it "indexes a shard with no README at all" do
      shard = indexable
      github = RecordedGithub.new("kemalcr/kemal")
        .tags("v1.0.0")
        .file("v1.0.0", "shard.yml", "name: kemal\n")

      result = RecordedGithub.install(github) { ShardIndexer.index(shard) }

      result.outcome.should eq(ShardIndexer::Outcome::Indexed)
      reload(shard).readme_content.should be_nil
    end

    it "does not fail the shard when the README fetch errors" do
      shard = indexable
      github = RecordedGithub.new("kemalcr/kemal")
        .tags("v1.0.0")
        .file("v1.0.0", "shard.yml", "name: kemal\n")
        .file_status("v1.0.0", "README.md", 500)

      result = RecordedGithub.install(github) { ShardIndexer.index(shard) }

      result.outcome.should eq(ShardIndexer::Outcome::Indexed)
      reload(shard).readme_content.should be_nil
      # A host that just errored is not asked five more times for five more
      # spellings.
      github.requested.count(&.includes?("readme.md")).should eq(0)
    end
  end

  describe "a repository with no tags" do
    it "gets a branch row rather than being skipped" do
      # Otherwise a large part of the corpus reads as a shard with no versions,
      # and gets no manifest, no dependency edges and no docs.
      shard = indexable
      github = RecordedGithub.new("kemalcr/kemal")
        .repository(default_branch: "master", pushed_at: Time.utc(2026, 1, 1))
        .file("master", "shard.yml", "name: kemal\nversion: 0.1.0\n")

      result = RecordedGithub.install(github) { ShardIndexer.index(shard) }

      result.outcome.should eq(ShardIndexer::Outcome::Indexed)
      result.versions.should eq(1)

      rows = versions_of(shard)
      rows.size.should eq(1)
      rows.first.version.should eq("master")
      rows.first.source.should eq(ShardVersion::Source::BRANCH)
      rows.first.release?.should be_false
      rows.first.spec_yaml.should eq("name: kemal\nversion: 0.1.0\n")

      reload(shard).latest_version.should eq("master")
    end

    it "indexes the repository even when it has no default branch either" do
      shard = indexable
      github = RecordedGithub.new("kemalcr/kemal").repository(stars: 5)

      result = RecordedGithub.install(github) { ShardIndexer.index(shard) }

      result.outcome.should eq(ShardIndexer::Outcome::Indexed)
      result.versions.should eq(0)
      versions_of(shard).should be_empty

      row = reload(shard)
      row.github_stars.should eq(5)
      row.latest_version.should be_nil
      row.indexed_at.should_not be_nil
    end
  end

  describe "a manifest that is missing or broken" do
    it "records an absent shard.yml at a tag and still indexes the shard" do
      # Discovery found this repository BY its shard.yml, so an absent one at a
      # tag means the manifest was added after that tag was cut. That is a fact
      # about the repository, not a gap in the registry.
      shard = indexable
      github = RecordedGithub.new("kemalcr/kemal").tags("v0.1.0")

      result = RecordedGithub.install(github) { ShardIndexer.index(shard) }

      result.outcome.should eq(ShardIndexer::Outcome::Indexed)

      version = version_of(shard, "0.1.0")
      version.spec_error.should eq("No shard.yml at tag v0.1.0.")
      version.spec_yaml.should be_nil
      version.indexed?.should be_true

      reload(shard).index_error.should be_nil
    end

    it "names the branch rather than a tag when there are no tags" do
      shard = indexable
      github = RecordedGithub.new("kemalcr/kemal").repository(default_branch: "main")

      RecordedGithub.install(github) { ShardIndexer.index(shard) }

      version_of(shard, "main").spec_error.should eq("No shard.yml on branch main.")
    end

    it "distinguishes a fetch that failed from a manifest that is not there" do
      # Absent is a fact about the repository and is final; failed is a fact
      # about the fetch and a later pass retries it.
      shard = indexable
      github = RecordedGithub.new("kemalcr/kemal")
        .tags("v1.0.0")
        .file_status("v1.0.0", "shard.yml", 500)

      RecordedGithub.install(github) { ShardIndexer.index(shard) }

      version_of(shard, "1.0.0").spec_error
        .should eq("shard.yml could not be fetched at v1.0.0: HTTP 500.")
    end

    it "records a parse error as a sentence a reader can act on" do
      shard = indexable
      github = RecordedGithub.new("kemalcr/kemal")
        .tags("v1.0.0")
        .file("v1.0.0", "shard.yml", "name: broken\ndependencies:\n\tkemal:\n")

      result = RecordedGithub.install(github) { ShardIndexer.index(shard) }

      result.outcome.should eq(ShardIndexer::Outcome::Indexed)

      version = version_of(shard, "1.0.0")
      version.spec_error.not_nil!.should start_with("shard.yml is not valid YAML")
      version.spec_error.not_nil!.should_not contain("Exception")
      # The raw text is kept so a parser fix can re-read it without spending
      # rate limit.
      version.spec_yaml.should eq("name: broken\ndependencies:\n\tkemal:\n")
    end

    it "clears a previous pass's parse rather than keeping it" do
      # The failure this prevents: a tag that was force-pushed with a broken
      # manifest keeps showing the crystal version, dependencies and targets of
      # a manifest it no longer has.
      shard = indexable
      good = RecordedGithub.new("kemalcr/kemal")
        .tags("v1.0.0")
        .file("v1.0.0", "shard.yml", <<-YAML)
          name: kemal
          crystal: ">= 1.12.0"
          targets:
            kemal:
              main: src/kemal.cr
          executables:
            - kemal
          YAML

      RecordedGithub.install(good) { ShardIndexer.index(shard) }

      first = version_of(shard, "1.0.0")
      first.crystal_version.should eq(">= 1.12.0")
      first.target_names.should eq(["kemal"])
      first.executable_names.should eq(["kemal"])
      first.metadata.should_not be_nil

      broken = RecordedGithub.new("kemalcr/kemal")
        .tags("v1.0.0")
        .file("v1.0.0", "shard.yml", "false")

      RecordedGithub.install(broken) { ShardIndexer.index(reload(shard)) }

      second = version_of(shard, "1.0.0")
      second.spec_error.not_nil!.should contain("not a mapping")
      second.crystal_version.should be_nil
      second.metadata.should be_nil
      second.targets.should be_nil
      second.executables.should be_nil
      second.target_names.should be_empty
    end

    it "leaves an older version's stored manifest alone on a later pass" do
      # Only the version actually fetched gets manifest fields written. A pass
      # that indexes 2.0.0 must not blank out what 1.0.0 already knows.
      shard = indexable
      first_pass = RecordedGithub.new("kemalcr/kemal")
        .tags("v1.0.0")
        .file("v1.0.0", "shard.yml", "name: kemal\ncrystal: \">= 1.0.0\"\n")

      RecordedGithub.install(first_pass) { ShardIndexer.index(shard) }
      version_of(shard, "1.0.0").crystal_version.should eq(">= 1.0.0")

      second_pass = RecordedGithub.new("kemalcr/kemal")
        .tags("v2.0.0", "v1.0.0")
        .file("v2.0.0", "shard.yml", "name: kemal\ncrystal: \">= 1.12.0\"\n")

      RecordedGithub.install(second_pass) { ShardIndexer.index(reload(shard)) }

      version_of(shard, "1.0.0").crystal_version.should eq(">= 1.0.0")
      version_of(shard, "2.0.0").crystal_version.should eq(">= 1.12.0")
      reload(shard).latest_version.should eq("2.0.0")
    end
  end

  describe "a repository that is gone" do
    it "marks the row unavailable without deleting it" do
      # Download counts, dependency edges and inbound links still point at this
      # shard, and repositories come back.
      shard = indexable
      ShardVersionFactory.create &.shard_id(shard.id).version("1.0.0")

      github = RecordedGithub.new("kemalcr/kemal").repository_status(404)

      result = RecordedGithub.install(github) { ShardIndexer.index(shard) }

      result.outcome.should eq(ShardIndexer::Outcome::Unavailable)

      row = reload(shard)
      row.unavailable_at.should_not be_nil
      row.unavailable?.should be_true
      row.index_error.not_nil!.should contain("not a repository this token can see")
      row.indexed_at.should be_nil

      ShardQuery.new.id(shard.id).first?.should_not be_nil
      versions_of(shard).map(&.version).should eq(["1.0.0"])
    end

    it "clears the unavailable mark when the repository answers again" do
      shard = indexable
      RecordedGithub.install(RecordedGithub.new("kemalcr/kemal").repository_status(404)) do
        ShardIndexer.index(shard)
      end
      reload(shard).unavailable_at.should_not be_nil

      back = RecordedGithub.new("kemalcr/kemal").repository(stars: 1).tags("v1.0.0")
      RecordedGithub.install(back) { ShardIndexer.index(reload(shard)) }

      row = reload(shard)
      row.unavailable_at.should be_nil
      row.index_error.should be_nil
      row.indexed_at.should_not be_nil
    end

    it "records a refused read as failed rather than unavailable, so it retries" do
      shard = indexable
      github = RecordedGithub.new("kemalcr/kemal").repository_status(403)

      result = RecordedGithub.install(github) { ShardIndexer.index(shard) }

      result.outcome.should eq(ShardIndexer::Outcome::Failed)

      row = reload(shard)
      row.unavailable_at.should be_nil
      row.index_error.not_nil!.should contain("403")
      row.indexed_at.should be_nil
    end

    # A renamed or transferred repository answers 301, and that used to land in
    # the catch-all and be recorded as "metadata answered HTTP 301": a fault,
    # retried on every pass forever, on a row that will never answer under that
    # name again. It is not a fault. That owner and name have stopped naming a
    # repository, which is what unavailable means.
    #
    # This matters more now that the dependency graph is a discovery source.
    # Manifests outlive renames, so they name repositories under their old
    # identities long after the move: a sample of 599 indexed manifests named
    # 20 such repositories, every one of which would otherwise become a
    # permanently erroring blank row.
    it "marks a renamed repository unavailable rather than erroring forever" do
      shard = indexable
      github = RecordedGithub.new("kemalcr/kemal").repository_status(301)

      result = RecordedGithub.install(github) { ShardIndexer.index(shard) }

      result.outcome.should eq(ShardIndexer::Outcome::Unavailable)

      row = reload(shard)
      row.unavailable_at.should_not be_nil
      row.index_error.not_nil!.should contain("has moved")
      row.indexed_at.should be_nil
    end
  end

  describe "hosts" do
    it "indexes a gitlab.com shard rather than recording it unsupported" do
      # This is the behaviour that changed: the indexer resolves through
      # RepositorySourceFactory, which reads all four hosts the crawler finds.
      # Gating on github.com left three hosts' shards permanently blank.
      shard = indexable(owner: "acme", repo: "router", host: "gitlab.com")
      github = RecordedGithub.new("acme/router")
        .repository(stars: 12, default_branch: "main")
        .tags("v0.3.0")
        .file("v0.3.0", "shard.yml", "name: router\n")

      result = RecordedGithub.install(github) { ShardIndexer.index(shard) }

      result.outcome.should eq(ShardIndexer::Outcome::Indexed)
      github.asked.should eq(["gitlab.com"])
      reload(shard).github_stars.should eq(12)
    end

    it "records a host outside the four the registry reads as unsupported" do
      # Counted rather than silently never gaining content, so a sweep's
      # arithmetic describes reality: "attempted 300, indexed 40" with 260
      # unaccounted for is how a whole host stays empty without anyone noticing.
      shard = shard_hosted_on("git.sr.ht", "someone", "hut")

      result = ShardIndexer.index(shard)

      result.outcome.should eq(ShardIndexer::Outcome::Unsupported)
      result.detail.not_nil!.should contain("git.sr.ht")

      row = reload(shard)
      row.index_error.not_nil!.should contain("not a host the registry can read")
      row.indexed_at.should be_nil
      # Claimed, so it cannot sit at the head of the queue forever.
      row.index_attempted_at.should_not be_nil
      # Not deleted: inbound links and dependency edges still point at it.
      ShardQuery.new.id(shard.id).first?.should_not be_nil
    end

    it "records a pre-identity row with no host at all the same way" do
      # A legacy row reaches the same branch through a NULL host rather than a
      # foreign one, and must be counted rather than read as un-indexed.
      shard = legacy_row("orphan", "https://github.com/kemalcr/kemal")

      result = ShardIndexer.index(shard)

      result.outcome.should eq(ShardIndexer::Outcome::Unsupported)
      reload(shard).index_attempted_at.should_not be_nil
    end

    # The bug this branch was written for and could not reach.
    #
    # claim and finish used to write through SaveShard, which requires host,
    # owner, repo and canonical_slug. A row with none of those raised inside the
    # claim, before it could be stamped, so it came back at the head of the
    # queue on every run forever: the poison shard that claiming first exists to
    # prevent, caused by the claim. Both now write the bookkeeping columns
    # directly, because a row we cannot read is the one that most needs
    # recording as attempted.
    #
    # host is set and owner/repo are not, which is the only combination that
    # reaches repo_path.nil?. A NULL host stops at the unsupported gate above.
    it "stamps a row with a host but no owner or repo instead of raising" do
      shard = legacy_row("no-repo", "https://github.com/")
      AppDatabase.exec("UPDATE shards SET host = 'github.com' WHERE id = $1", shard.id)
      shard = ShardQuery.new.id(shard.id).first

      result = ShardIndexer.index(shard)

      result.outcome.should eq(ShardIndexer::Outcome::Failed)
      result.detail.not_nil!.should contain("nothing to fetch")

      row = reload(shard)
      row.index_attempted_at.should_not be_nil
      row.index_error.not_nil!.should contain("nothing to fetch")
    end
  end

  describe "claiming before fetching" do
    it "stamps index_attempted_at before any request is made" do
      shard = indexable
      github = RecordedGithub.new("kemalcr/kemal").tags("v1.0.0")

      reload(shard).index_attempted_at.should be_nil

      RecordedGithub.install(github) { ShardIndexer.index(shard) }

      reload(shard).index_attempted_at.should_not be_nil
    end

    it "leaves the claim on a shard whose fetch raised, so it cannot block the queue" do
      # The poison-repository case. A process killed or blown up mid-shard
      # leaves attempted set with indexed_at and index_error both nil, which
      # reads as exactly what it is and sorts to the BACK of the queue. Stamping
      # after the writes instead would turn one bad repository into a
      # permanently stuck sweep.
      shard = indexable
      github = RecordedGithub.new("kemalcr/kemal").raising("connection reset")

      expect_raises(Exception, "connection reset") do
        RecordedGithub.install(github) { ShardIndexer.index(shard) }
      end

      row = reload(shard)
      row.index_attempted_at.should_not be_nil
      row.indexed_at.should be_nil
      row.index_error.should be_nil
    end

    it "advances the claim on every pass, so a run cannot stall on one shard" do
      shard = indexable
      github = RecordedGithub.new("kemalcr/kemal").tags("v1.0.0")

      RecordedGithub.install(github) { ShardIndexer.index(shard) }
      first = reload(shard).index_attempted_at.not_nil!

      RecordedGithub.install(github) { ShardIndexer.index(reload(shard)) }
      second = reload(shard).index_attempted_at.not_nil!

      second.should be >= first
    end
  end

  describe "running twice" do
    it "converges rather than duplicating version rows" do
      shard = indexable
      github = RecordedGithub.new("kemalcr/kemal")
        .repository(stars: 10)
        .tags("v1.1.0", "v1.0.0")
        .file("v1.1.0", "shard.yml", "name: kemal\n")

      RecordedGithub.install(github) do
        ShardIndexer.index(shard)
        ShardIndexer.index(reload(shard))
        ShardIndexer.index(reload(shard))
      end

      versions_of(shard).map(&.version).sort!.should eq(["1.0.0", "1.1.0"])
      ShardQuery.new.id(shard.id).select_count.should eq(1)
    end

    it "keeps a version's real commit date when a later pass rereads the tag list" do
      # An already-dated version must not have its date overwritten by the
      # repository's pushed_at fallback on the next pass.
      shard = indexable
      dated = Time.utc(2025, 5, 5)

      first = RecordedGithub.new("kemalcr/kemal")
        .repository(pushed_at: Time.utc(2026, 1, 1))
        .tags("v1.0.0")
        .file("v1.0.0", "shard.yml", "name: kemal\n")
        .dated("v1.0.0", dated)

      RecordedGithub.install(first) { ShardIndexer.index(shard) }
      version_of(shard, "1.0.0").released_at.to_unix.should eq(dated.to_unix)

      later = RecordedGithub.new("kemalcr/kemal")
        .repository(pushed_at: Time.utc(2026, 6, 1))
        .tags("v2.0.0", "v1.0.0")
        .file("v2.0.0", "shard.yml", "name: kemal\n")

      RecordedGithub.install(later) { ShardIndexer.index(reload(shard)) }

      version_of(shard, "1.0.0").released_at.to_unix.should eq(dated.to_unix)
    end
  end
end
