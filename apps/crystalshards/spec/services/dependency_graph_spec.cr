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

# The dependent count a shard page renders: distinct shards, through their
# versions, that name this one. The same query the report states.
private def dependent_shards(shard : Shard) : Int64
  AppDatabase.query_one(
    <<-SQL,
    SELECT COUNT(DISTINCT shard_versions.shard_id)
    FROM dependencies
    JOIN shard_versions ON shard_versions.id = dependencies.shard_version_id
    WHERE dependencies.dependent_shard_id = $1
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

  it "clears the graph when the manifest stops being readable" do
    radix = shard_at("github.com", "luislavena", "radix", "radix")
    consumer = shard_at("github.com", "acme", "regressing", "regressing")

    before = RecordedGithub.new("acme/regressing")
      .repository(default_branch: "main")
      .tags("v1.0.0")
      .file("v1.0.0", "shard.yml", RADIX_ONLY)

    RecordedGithub.install(before) { ShardIndexer.index(consumer) }
    dependent_shards(radix).should eq(1)

    # A tag whose shard.yml has gone keeps no stored manifest, so it must keep
    # no edges either: leaving them would show dependencies the tag does not
    # declare.
    after = RecordedGithub.new("acme/regressing")
      .repository(default_branch: "main")
      .tags("v1.0.0")
      .missing("v1.0.0", "shard.yml")

    result = RecordedGithub.install(after) { ShardIndexer.index(reload(consumer)) }

    result.dependencies.should eq(0)
    indexed_edges(consumer).select_count.should eq(0)
    dependent_shards(radix).should eq(0)
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
