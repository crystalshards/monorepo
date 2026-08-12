require "../spec_helper"
require "../../src/services/index_sweep"

# The dependents half of the popularity signal, written by indexing.
#
# Stars arrive as one field off the repository. "How many other shards depend
# on this one" is not a field any host reports: it is counted from dependency
# rows, and those rows exist only if indexing writes them. These specs are
# about that write happening, from a manifest, through ShardIndexer, with
# nothing listening on a port.
private def shard_at(host : String, owner : String, repo : String, name : String) : Shard
  ShardFactory.create &.name(name).repository_url("https://#{host}/#{owner}/#{repo}")
end

private def reload(shard : Shard) : Shard
  ShardQuery.new.id(shard.id).first
end

# The edges belonging to the one version this pass fetched a manifest for.
private def indexed_edges(shard : Shard) : DependencyQuery
  version = ShardVersionQuery.new.shard_id(shard.id).indexed_at.is_not_nil.first
  DependencyQuery.new.shard_version_id(version.id)
end

# The dependent count a shard page renders: distinct OTHER shards, through
# their versions, that name this one. The self-edge predicate matches the one
# in the popularity query, because a manifest listing its own shard would
# otherwise let a shard be its own dependent.
private def dependent_shards(shard : Shard) : Int64
  AppDatabase.query_one(
    <<-SQL,
    SELECT COUNT(DISTINCT shard_versions.shard_id)
    FROM dependencies
    JOIN shard_versions ON shard_versions.id = dependencies.shard_version_id
    WHERE dependencies.dependent_shard_id = $1
      AND shard_versions.shard_id <> dependencies.dependent_shard_id
    SQL
    shard.id, as: Int64
  )
end

private RADIX_ONLY = <<-YAML
  name: consumer
  version: 1.0.0
  dependencies:
    radix:
      github: luislavena/radix
  YAML

describe "dependency graph written by indexing" do
  it "writes an edge per declared dependency the registry already knows" do
    radix = shard_at("github.com", "luislavena", "radix", "radix")
    exception_page = shard_at("github.com", "crystal-loot", "exception_page", "exception_page")
    ameba = shard_at("github.com", "crystal-ameba", "ameba", "ameba")
    consumer = shard_at("github.com", "acme", "consumer", "consumer")

    manifest = <<-YAML
      name: consumer
      version: 1.0.0
      dependencies:
        radix:
          github: luislavena/radix
        exception_page:
          github: crystal-loot/exception_page
      development_dependencies:
        ameba:
          github: crystal-ameba/ameba
      YAML

    recorded = RecordedGithub.new("acme/consumer")
      .repository(stars: 12, default_branch: "master")
      .tags("v1.0.0")
      .file("v1.0.0", "shard.yml", manifest)

    result = RecordedGithub.install(recorded) { ShardIndexer.index(consumer) }

    result.outcome.should eq(ShardIndexer::Outcome::Indexed)
    result.dependencies.should eq(3)

    edges = indexed_edges(consumer)
    edges.select_count.should eq(3)
    edges.name("radix").first.dependent_shard_id.should eq(radix.id)
    edges.name("exception_page").first.dependent_shard_id.should eq(exception_page.id)
    edges.name("ameba").first.dependent_shard_id.should eq(ameba.id)
    edges.name("ameba").first.scope.should eq("development")

    # The point of the exercise: each of those shards can now count a
    # dependent, where before indexing wrote nothing and every count was zero.
    dependent_shards(radix).should eq(1)
    dependent_shards(exception_page).should eq(1)
    dependent_shards(ameba).should eq(1)
  end

  it "resolves a dependency without asking any host about it" do
    # RecordedGithub.install raises for any repo_path it was not scripted with,
    # so radix resolving at all proves the resolver read this database and
    # spent no rate limit: only the consumer's own repository is scripted.
    radix = shard_at("github.com", "luislavena", "radix", "radix")
    consumer = shard_at("github.com", "acme", "quiet", "quiet-consumer")

    recorded = RecordedGithub.new("acme/quiet")
      .repository(default_branch: "main")
      .tags("v1.0.0")
      .file("v1.0.0", "shard.yml", RADIX_ONLY)

    RecordedGithub.install(recorded) { ShardIndexer.index(consumer) }

    indexed_edges(consumer).name("radix").first.dependent_shard_id.should eq(radix.id)
    recorded.requested.none?(&.includes?("luislavena/radix")).should be_true
  end

  it "records a dependency on a shard the registry has never seen, and still indexes" do
    consumer = shard_at("github.com", "acme", "pioneer", "pioneer")

    manifest = <<-YAML
      name: pioneer
      dependencies:
        radix:
          github: luislavena/radix
        mystery: ~> 4.1
      YAML

    recorded = RecordedGithub.new("acme/pioneer")
      .repository(stars: 3, default_branch: "main")
      .tags("v1.0.0")
      .file("v1.0.0", "shard.yml", manifest)

    result = RecordedGithub.install(recorded) { ShardIndexer.index(consumer) }

    # Neither a failure nor a silently dropped row. Both requirements are
    # recorded; neither claims to point at a repository the registry cannot
    # name.
    result.outcome.should eq(ShardIndexer::Outcome::Indexed)
    result.dependencies.should eq(2)

    edges = indexed_edges(consumer)
    edges.select_count.should eq(2)

    by_source = edges.name("radix").first
    by_source.dependent_shard_id.should be_nil
    by_source.version_requirement.should eq("*")

    by_name = edges.name("mystery").first
    by_name.dependent_shard_id.should be_nil
    by_name.version_requirement.should eq("~> 4.1")
  end

  it "does not duplicate edges when the same version is indexed again" do
    radix = shard_at("github.com", "luislavena", "radix", "radix")
    consumer = shard_at("github.com", "acme", "repeat", "repeat")

    recorded = RecordedGithub.new("acme/repeat")
      .repository(default_branch: "main")
      .tags("v1.0.0")
      .file("v1.0.0", "shard.yml", RADIX_ONLY)

    RecordedGithub.install(recorded) do
      ShardIndexer.index(consumer)
      ShardIndexer.index(reload(consumer))
      ShardIndexer.index(reload(consumer))
    end

    indexed_edges(consumer).select_count.should eq(1)
    dependent_shards(radix).should eq(1)
  end

  it "drops an edge the manifest no longer declares" do
    radix = shard_at("github.com", "luislavena", "radix", "radix")
    dropped = shard_at("github.com", "crystal-loot", "exception_page", "exception_page")
    consumer = shard_at("github.com", "acme", "shrinking", "shrinking")

    both = <<-YAML
      name: shrinking
      dependencies:
        radix:
          github: luislavena/radix
        exception_page:
          github: crystal-loot/exception_page
      YAML

    before = RecordedGithub.new("acme/shrinking")
      .repository(default_branch: "main")
      .tags("v1.0.0")
      .file("v1.0.0", "shard.yml", both)

    RecordedGithub.install(before) { ShardIndexer.index(consumer) }
    indexed_edges(consumer).select_count.should eq(2)
    dependent_shards(dropped).should eq(1)

    after = RecordedGithub.new("acme/shrinking")
      .repository(default_branch: "main")
      .tags("v1.0.0")
      .file("v1.0.0", "shard.yml", RADIX_ONLY)

    RecordedGithub.install(after) { ShardIndexer.index(reload(consumer)) }

    edges = indexed_edges(consumer)
    edges.select_count.should eq(1)
    edges.name("exception_page").first?.should be_nil
    dependent_shards(radix).should eq(1)
    dependent_shards(dropped).should eq(0)
  end

  it "clears the graph when the host says the manifest is gone" do
    radix = shard_at("github.com", "luislavena", "radix", "radix")
    consumer = shard_at("github.com", "acme", "regressing", "regressing")

    before = RecordedGithub.new("acme/regressing")
      .repository(default_branch: "main")
      .tags("v1.0.0")
      .file("v1.0.0", "shard.yml", RADIX_ONLY)

    RecordedGithub.install(before) { ShardIndexer.index(consumer) }
    dependent_shards(radix).should eq(1)

    # The host answered: there is no shard.yml here. That is a fact about the
    # repository, so the stored manifest goes and the edges derived from it go
    # with it. Keeping them would list dependencies beside a page that says the
    # manifest could not be read.
    after = RecordedGithub.new("acme/regressing")
      .repository(default_branch: "main")
      .tags("v1.0.0")
      .missing("v1.0.0", "shard.yml")

    result = RecordedGithub.install(after) { ShardIndexer.index(reload(consumer)) }

    result.dependencies.should eq(0)
    indexed_edges(consumer).select_count.should eq(0)
    dependent_shards(radix).should eq(0)
  end

  it "clears the graph when the manifest stops parsing" do
    radix = shard_at("github.com", "luislavena", "radix", "radix")
    consumer = shard_at("github.com", "acme", "broken", "broken")

    before = RecordedGithub.new("acme/broken")
      .repository(default_branch: "main")
      .tags("v1.0.0")
      .file("v1.0.0", "shard.yml", RADIX_ONLY)

    RecordedGithub.install(before) { ShardIndexer.index(consumer) }
    dependent_shards(radix).should eq(1)

    # Same reasoning as an absent manifest. The host served the file and it is
    # not a shard specification, which the version records in spec_error; a
    # dependency list rendered next to that sentence would contradict it.
    after = RecordedGithub.new("acme/broken")
      .repository(default_branch: "main")
      .tags("v1.0.0")
      .file("v1.0.0", "shard.yml", "name: broken\n  dependencies: [\n")

    RecordedGithub.install(after) { ShardIndexer.index(reload(consumer)) }

    indexed_edges(consumer).select_count.should eq(0)
    dependent_shards(radix).should eq(0)
  end

  it "keeps the graph when the host fails to answer for the manifest" do
    radix = shard_at("github.com", "luislavena", "radix", "radix")
    consumer = shard_at("github.com", "acme", "flaky", "flaky")

    before = RecordedGithub.new("acme/flaky")
      .repository(default_branch: "main")
      .tags("v1.0.0")
      .file("v1.0.0", "shard.yml", RADIX_ONLY)

    RecordedGithub.install(before) { ShardIndexer.index(consumer) }
    dependent_shards(radix).should eq(1)

    # A 500 from the file endpoint is news about the host, not about the ref.
    # The ref still declares what it declared, so deleting its edges would drop
    # radix out of every dependent count over one bad second, invisibly, until
    # some later pass happened to succeed.
    after = RecordedGithub.new("acme/flaky")
      .repository(default_branch: "main")
      .tags("v1.0.0")
      .file_status("v1.0.0", "shard.yml", 500)

    result = RecordedGithub.install(after) { ShardIndexer.index(reload(consumer)) }

    # Nothing written this pass, and nothing destroyed either.
    result.outcome.should eq(ShardIndexer::Outcome::Indexed)
    result.dependencies.should eq(0)
    indexed_edges(consumer).name("radix").first.dependent_shard_id.should eq(radix.id)
    dependent_shards(radix).should eq(1)

    # And the preservation is durable, not just true until something else runs.
    # The stored manifest was kept too, so the queue path, which reads that row
    # and replaces the whole set from it, still finds the dependency there
    # rather than deleting an edge it can no longer see a reason for.
    UpdateDependenciesWorker.new(shard_name: "github.com/acme/flaky", version: "1.0.0").perform

    indexed_edges(consumer).name("radix").first.dependent_shard_id.should eq(radix.id)
    dependent_shards(radix).should eq(1)

    # The retry contract, end to end. `Failed` is a fact about the fetch, and
    # IndexSweep's queue is ordered by index_attempted_at staleness alone, so a
    # later pass returns to this shard whatever its outcome was and re-reads
    # shard.yml. When the host answers again the preserved graph is replaced by
    # what the manifest now says, so preservation delays the update rather than
    # freezing it.
    recovered = RecordedGithub.new("acme/flaky")
      .repository(default_branch: "main")
      .tags("v1.0.0")
      .file("v1.0.0", "shard.yml", <<-YAML)
        name: flaky
        dependencies:
          exception_page:
            github: crystal-loot/exception_page
        YAML

    moved_to = shard_at("github.com", "crystal-loot", "exception_page", "exception_page")
    result = RecordedGithub.install(recovered) { ShardIndexer.index(reload(consumer)) }

    result.dependencies.should eq(1)
    indexed_edges(consumer).name("radix").first?.should be_nil
    dependent_shards(radix).should eq(0)
    dependent_shards(moved_to).should eq(1)
  end

  it "resolves only the version whose manifest was fetched" do
    shard_at("github.com", "luislavena", "radix", "radix")
    consumer = shard_at("github.com", "acme", "tagged", "tagged")

    manifest = <<-YAML
      name: tagged
      dependencies:
        radix:
          github: luislavena/radix
      YAML

    recorded = RecordedGithub.new("acme/tagged")
      .repository(default_branch: "main")
      .tags("v3.0.0", "v2.0.0", "v1.0.0")
      .file("v3.0.0", "shard.yml", manifest)

    result = RecordedGithub.install(recorded) { ShardIndexer.index(consumer) }

    # Three versions, one manifest, one edge. A shard with 65 tags stays one
    # unit of dependency work rather than 65.
    result.versions.should eq(3)
    result.dependencies.should eq(1)
    DependencyQuery.new.select_count.should eq(1)
  end
end

describe "dependency edges in a sweep report" do
  it "totals the edges a pass wrote" do
    radix = shard_at("github.com", "luislavena", "radix", "radix")
    first = shard_at("github.com", "acme", "one", "one")
    second = shard_at("github.com", "acme", "two", "two")

    one_manifest = <<-YAML
      name: one
      dependencies:
        radix:
          github: luislavena/radix
      YAML

    two_manifest = <<-YAML
      name: two
      dependencies:
        radix:
          github: luislavena/radix
        one: ~> 1.0
      YAML

    recordings = {
      "luislavena/radix" => RecordedGithub.new("luislavena/radix")
        .repository(default_branch: "master"),
      "acme/one" => RecordedGithub.new("acme/one")
        .repository(default_branch: "main")
        .tags("v1.0.0")
        .file("v1.0.0", "shard.yml", one_manifest),
      "acme/two" => RecordedGithub.new("acme/two")
        .repository(default_branch: "main")
        .tags("v1.0.0")
        .file("v1.0.0", "shard.yml", two_manifest),
    }

    report = RecordedGithub.install(recordings) do
      IndexSweep.run(IndexSweep::Options.new(max_shards: 10, min_age: 1.hour))
    end

    report.indexed.should eq(3)
    report.dependencies.should eq(3)
    report.to_s.should contain("3 dependency edges")

    # radix is depended on by two distinct shards, which is the number a shard
    # page renders next to its star count.
    dependent_shards(radix).should eq(2)
    dependent_shards(first).should eq(1)
    dependent_shards(second).should eq(0)
  end
end
