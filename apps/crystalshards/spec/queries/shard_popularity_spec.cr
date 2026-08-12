require "../spec_helper"

# Wires up "depender declares a dependency on target", at one version.
# Top level because Crystal cannot declare a def inside a describe block.
def declare_dependency(depender : Shard, target : Shard, version : String = "1.0.0")
  shard_version = ShardVersionFactory.create &.shard_id(depender.id).version(version)
  DependencyFactory.create &.shard_version_id(shard_version.id).dependent_shard_id(target.id)
  shard_version
end

# The two rules every dependents query has to honour, and the reason each
# exists, are spelled out in src/queries/shard_popularity.cr. These specs pin
# both, because getting either wrong produces a plausible-looking number rather
# than an error.
describe ShardPopularity do
  describe ".dependent_count" do
    it "counts other shards that depend on this one" do
      target = ShardFactory.create &.name("target")
      declare_dependency(ShardFactory.create(&.name("a")), target)
      declare_dependency(ShardFactory.create(&.name("b")), target)

      ShardPopularity.dependent_count(target.id).should eq(2)
    end

    it "counts a depender once however many releases declare the dependency" do
      # UpdateDependenciesWorker writes one edge per version, so a project with
      # eight releases would be eight dependents without DISTINCT.
      target = ShardFactory.create &.name("target")
      depender = ShardFactory.create &.name("depender")

      declare_dependency(depender, target, "1.0.0")
      declare_dependency(depender, target, "2.0.0")
      declare_dependency(depender, target, "3.0.0")

      ShardPopularity.dependent_count(target.id).should eq(1)
    end

    it "does not count a shard depending on itself" do
      # Declaring yourself as a development_dependency is a common
      # self-hosting pattern and is not a dependent.
      target = ShardFactory.create &.name("self-hosting")
      declare_dependency(target, target)

      ShardPopularity.dependent_count(target.id).should eq(0)
    end

    it "ignores dependency rows that resolved to no shard" do
      # A requirement on something we cannot identify is recorded with a null
      # dependent_shard_id. It is a real requirement but not a dependent edge.
      target = ShardFactory.create &.name("target")
      orphan_version = ShardVersionFactory.create &.shard_id(ShardFactory.create(&.name("x")).id)
      DependencyFactory.create &.shard_version_id(orphan_version.id).name("unknown-thing")

      ShardPopularity.dependent_count(target.id).should eq(0)
    end

    it "is zero for a shard nothing depends on" do
      lonely = ShardFactory.create &.name("lonely")

      ShardPopularity.dependent_count(lonely.id).should eq(0)
    end
  end

  describe ".dependent_counts" do
    it "answers for every id asked about, including shards with none" do
      popular = ShardFactory.create &.name("popular")
      ignored = ShardFactory.create &.name("ignored")
      declare_dependency(ShardFactory.create(&.name("a")), popular)

      counts = ShardPopularity.dependent_counts([popular.id, ignored.id])

      counts[popular.id].should eq(1)
      # Present and zero, not missing. Cards index this hash directly.
      counts[ignored.id].should eq(0)
    end

    it "agrees with the single-shard count under the same graph" do
      target = ShardFactory.create &.name("target")
      depender = ShardFactory.create &.name("depender")
      declare_dependency(depender, target, "1.0.0")
      declare_dependency(depender, target, "2.0.0")
      declare_dependency(ShardFactory.create(&.name("b")), target)
      declare_dependency(target, target)

      bulk = ShardPopularity.dependent_counts([target.id])

      bulk[target.id].should eq(ShardPopularity.dependent_count(target.id))
      bulk[target.id].should eq(2)
    end

    it "returns an empty hash for no ids rather than querying" do
      ShardPopularity.dependent_counts([] of Int64).should be_empty
    end
  end

  describe ".dependent_ids" do
    it "returns each depending shard once, newest release first" do
      target = ShardFactory.create &.name("target")
      older = ShardFactory.create &.name("older")
      newer = ShardFactory.create &.name("newer")

      older_version = ShardVersionFactory.create &.shard_id(older.id)
        .released_at(Time.utc(2024, 1, 1))
      DependencyFactory.create &.shard_version_id(older_version.id).dependent_shard_id(target.id)

      newer_version = ShardVersionFactory.create &.shard_id(newer.id)
        .released_at(Time.utc(2025, 6, 1))
      DependencyFactory.create &.shard_version_id(newer_version.id).dependent_shard_id(target.id)

      ShardPopularity.dependent_ids(target.id).should eq([newer.id, older.id])
    end

    it "excludes the shard itself, matching dependent_count" do
      target = ShardFactory.create &.name("target")
      declare_dependency(target, target)

      ShardPopularity.dependent_ids(target.id).should be_empty
      ShardPopularity.dependent_count(target.id).should eq(0)
    end

    it "honours the limit" do
      target = ShardFactory.create &.name("target")
      3.times { |i| declare_dependency(ShardFactory.create(&.name("d#{i}")), target) }

      ShardPopularity.dependent_ids(target.id, limit: 2).size.should eq(2)
    end
  end

  describe ".star_totals" do
    it "reports zero coverage when no shard has been fetched" do
      # This is the case the homepage must not render as "0 stars". Coverage
      # zero means unmeasured, and the page says so instead of printing a
      # number that reads as a verdict.
      ShardFactory.create &.name("unfetched")

      counted, summed = ShardPopularity.star_totals

      counted.should eq(0)
      summed.should eq(0)
    end

    it "separates coverage from the sum" do
      ShardFactory.create &.name("measured-zero").github_stars(0)
      ShardFactory.create &.name("measured-many").github_stars(40)
      ShardFactory.create &.name("unfetched")

      counted, summed = ShardPopularity.star_totals

      # Two shards measured, one of them genuinely at zero stars.
      counted.should eq(2)
      summed.should eq(40)
    end
  end

  describe ".dependency_link_total" do
    it "counts a shard pair once however many versions declare it" do
      target = ShardFactory.create &.name("target")
      depender = ShardFactory.create &.name("depender")
      declare_dependency(depender, target, "1.0.0")
      declare_dependency(depender, target, "2.0.0")

      ShardPopularity.dependency_link_total.should eq(1)
    end

    it "counts distinct pairs and skips self-references" do
      target = ShardFactory.create &.name("target")
      second = ShardFactory.create &.name("second")
      declare_dependency(ShardFactory.create(&.name("a")), target)
      declare_dependency(ShardFactory.create(&.name("b")), target)
      # Distinct versions: (shard_id, version) is unique, and target declares
      # two dependencies of its own, one of which is the self-reference.
      declare_dependency(target, second, "1.0.0")
      declare_dependency(target, target, "2.0.0")

      ShardPopularity.dependency_link_total.should eq(3)
    end

    it "is zero on an empty graph" do
      ShardFactory.create &.name("alone")

      ShardPopularity.dependency_link_total.should eq(0)
    end
  end
end
