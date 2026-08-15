require "../../spec_helper"

# Required directly, like the other discovery specs: src/app.cr carries only
# version_order out of services/, because these phases exist for a Cloud Run Job
# that never boots Lucky and have no business in the web server binary.
require "../../../src/services/discovery/dependency_sweep"
require "../../../src/services/shard_indexer"

# Discovery from the dependency graph.
#
# Nothing here touches a host, and that is the property under test as much as
# any count: the leads come out of Postgres and registering one is an insert, so
# a spec proving this works needs no recorded HTTP at all. The one exception is
# the end-to-end case, which runs the real indexer through RecordedGithub to
# prove the slug this phase reads is the slug indexing writes.
private def options(max_candidates : Int32 = 200) : Discovery::DependencySweep::Options
  Discovery::DependencySweep::Options.new(max_candidates: max_candidates)
end

private def rendered(report : Discovery::DependencySweep::Report) : String
  String.build { |io| Discovery::DependencySweep.render(report, io) }
end

private def shard_at(host : String, owner : String, repo : String) : Shard
  ShardFactory.create &.name(repo).at(host, owner, repo)
end

# An edge naming a repository, written the way indexing writes one. `slug` nil
# is a dependency that named a bare string and so names no repository;
# `dependent_shard` nil is one the registry had no row for when it was resolved.
private def edge(
  name : String,
  slug : String?,
  dependent_shard : Shard? = nil,
  version : ShardVersion = ShardVersionFactory.create,
) : Dependency
  dependency = DependencyFactory.create &.shard_version_id(version.id)
    .name(name)
    .dependent_shard_id(dependent_shard.try(&.id))

  AppDatabase.exec("UPDATE dependencies SET resolved_slug = $1 WHERE id = $2", slug, dependency.id)
  DependencyQuery.new.id(dependency.id).first
end

# The slugs a block added to the registry, and only those.
#
# Every edge needs an owning shard_version, and every shard_version brings a
# shard of its own, so the table is never empty when this phase runs. Asserting
# on a total would be asserting on the fixtures; the diff is the run.
private def slugs_registered_by(&) : Array(String)
  before = ShardQuery.new.to_a.compact_map(&.canonical_slug).to_set
  yield
  ShardQuery.new.to_a.compact_map(&.canonical_slug).reject { |slug| before.includes?(slug) }.sort
end

describe Discovery::DependencySweep do
  describe "Options" do
    it "defaults the bound when the variable is unset" do
      Discovery::DependencySweep::Options.parse(nil).max_candidates
        .should eq(Discovery::DependencySweep::DEFAULT_MAX_CANDIDATES)
    end

    it "takes a bound the operator set" do
      Discovery::DependencySweep::Options.parse("25").max_candidates.should eq(25)
    end

    # A typo silently becoming the default is how an operator ends up certain
    # they changed the budget and unable to see any effect.
    it "refuses a bound that is not a positive whole number" do
      expect_raises(Discovery::DependencySweep::ConfigurationError, /must be a positive whole number/) do
        Discovery::DependencySweep::Options.parse("plenty")
      end

      expect_raises(Discovery::DependencySweep::ConfigurationError, /got "0"/) do
        Discovery::DependencySweep::Options.parse("0")
      end
    end
  end

  describe ".due" do
    it "leads with the repository the most manifests depend on" do
      edge("radix", "github.com/luislavena/radix")
      edge("radix", "github.com/luislavena/radix")
      edge("radix", "github.com/luislavena/radix")
      edge("ameba", "github.com/crystal-ameba/ameba")
      edge("ameba", "github.com/crystal-ameba/ameba")
      edge("lonely", "codeberg.org/someone/lonely")

      Discovery::DependencySweep.due(10).map { |lead| {lead.slug, lead.references} }.should eq([
        {"github.com/luislavena/radix", 3_i64},
        {"github.com/crystal-ameba/ameba", 2_i64},
        {"codeberg.org/someone/lonely", 1_i64},
      ])
    end

    # The whole point of the column. Without it a dependency on something
    # unregistered is a null and a name, and a name is not a repository.
    it "ignores dependencies that name no repository" do
      edge("mystery", nil)

      Discovery::DependencySweep.due(10).should be_empty
    end

    it "ignores a repository the registry already has" do
      radix = shard_at("github.com", "luislavena", "radix")
      edge("radix", "github.com/luislavena/radix", dependent_shard: radix)

      Discovery::DependencySweep.due(10).should be_empty
    end

    # The stale-null case, and the reason the query joins shards rather than
    # trusting dependent_shard_id alone. An earlier run registered this
    # repository; the edge naming it keeps its null until the version is
    # reindexed. Without the join those slugs would fill the bound with work
    # already done, every run, forever.
    it "ignores a repository registered since the edge was last resolved" do
      edge("radix", "github.com/luislavena/radix")
      shard_at("github.com", "luislavena", "radix")

      Discovery::DependencySweep.due(10).should be_empty
    end

    it "takes at most the bound, highest reference count first" do
      edge("popular", "github.com/acme/popular")
      edge("popular", "github.com/acme/popular")
      edge("quiet", "github.com/acme/quiet")

      leads = Discovery::DependencySweep.due(1)
      leads.size.should eq(1)
      leads.first.slug.should eq("github.com/acme/popular")
    end

    # Manifests do occasionally disagree about what to call the same
    # repository. A run picking a different one each time would rewrite the
    # row's name on every pass.
    it "picks one deterministic name when manifests disagree" do
      version = ShardVersionFactory.create
      edge("zebra", "github.com/acme/thing", version: version)
      edge("apple", "github.com/acme/thing", version: ShardVersionFactory.create)

      Discovery::DependencySweep.due(10).first.name.should eq("apple")
    end
  end

  describe ".run" do
    it "registers a repository the dependency graph names and the crawler never found" do
      edge("radix", "github.com/luislavena/radix")

      report = Discovery::DependencySweep.run(options)

      report.registered.should eq(1)
      report.failed.should eq(0)

      shard = ShardQuery.new.canonical_slug("github.com/luislavena/radix").first
      shard.name.should eq("radix")
      shard.host.should eq("github.com")
      shard.owner.should eq("luislavena")
      shard.repo.should eq("radix")
      shard.repository_url.should eq("https://github.com/luislavena/radix")
      # Discovery writes identity and stops. Indexing is what gives it content,
      # and a nil indexed_at is the signal that says so.
      shard.indexed_at.should be_nil
    end

    # Not a GitHub-only mechanism, and this is the coverage it buys that no
    # crawler can: gitlab.com, codeberg.org and bitbucket.org have no
    # credential in production, so a shard on one of them is invisible to every
    # enumeration the registry runs. A manifest naming it is not.
    it "registers repositories on hosts no crawler has a credential for" do
      edge("router", "gitlab.com/acme/router")
      edge("widget", "codeberg.org/acme/widget")
      edge("gadget", "bitbucket.org/acme/gadget")

      report = uninitialized Discovery::DependencySweep::Report
      added = slugs_registered_by { report = Discovery::DependencySweep.run(options) }

      report.registered.should eq(3)
      added.should eq([
        "bitbucket.org/acme/gadget",
        "codeberg.org/acme/widget",
        "gitlab.com/acme/router",
      ])
    end

    # A host the registry cannot store is a coverage boundary, not a failure.
    # Counting it as one would fail the Job over a dependency on somebody's
    # self-hosted Gitea, and naming the host is what makes the number
    # actionable: it is the answer to "what would supporting this buy".
    it "reports a dependency on an unsupported host without failing the run" do
      edge("thing", "gitea.example.com/acme/thing")
      edge("other", "gitea.example.com/acme/other")
      edge("scoped", "git.sr.ht/user/scoped")

      report = uninitialized Discovery::DependencySweep::Report
      added = slugs_registered_by { report = Discovery::DependencySweep.run(options) }

      report.registered.should eq(0)
      report.failed.should eq(0)
      report.unsupported.should eq({"gitea.example.com" => 2, "git.sr.ht" => 1})
      report.ok?.should be_true
      added.should be_empty
    end

    # The reason the host filter is in the query rather than in the loop. An
    # unsupported lead can never be registered, so it never stops being a lead.
    # Counted against the bound it would take a slot from a registrable lead on
    # every run for the rest of time, and take it first whenever the ordering
    # favoured it, which alphabetically it often does.
    it "never spends the run's bound on a lead it can never register" do
      edge("aaa-unstorable", "gitea.example.com/acme/aaa")
      edge("zzz-storable", "github.com/acme/zzz")

      report = uninitialized Discovery::DependencySweep::Report
      added = slugs_registered_by { report = Discovery::DependencySweep.run(options(max_candidates: 1)) }

      added.should eq(["github.com/acme/zzz"])
      report.registered.should eq(1)
    end

    # A count that can never reach zero is a count nobody can act on, so the
    # backlog figure is scoped to leads this phase can actually clear.
    it "leaves no outstanding backlog once every registrable lead is taken" do
      edge("thing", "gitea.example.com/acme/thing")
      edge("storable", "github.com/acme/storable")

      Discovery::DependencySweep.run(options)

      Discovery::DependencySweep.outstanding.should eq(0)
      Discovery::DependencySweep.unsupported_hosts.should eq({"gitea.example.com" => 1})
    end

    # sr.ht owners really are spelled "~user", and the tilde is outside every
    # character the registry will put in a URL path. An sr.ht slug is therefore
    # excluded by the host filter like any other unsupported host, and never
    # reaches the identity check that would also have refused it.
    it "counts a repository with an unaddressable owner against its host" do
      edge("scoped", "git.sr.ht/~user/scoped")

      report = uninitialized Discovery::DependencySweep::Report
      added = slugs_registered_by { report = Discovery::DependencySweep.run(options) }

      report.attempted.should eq(0)
      report.failed.should eq(0)
      report.ok?.should be_true
      report.unsupported.should eq({"git.sr.ht" => 1})
      added.should be_empty
    end

    it "stops at the bound and leaves the rest for the next run" do
      edge("first", "github.com/acme/first")
      edge("second", "github.com/acme/second")
      edge("third", "github.com/acme/third")

      report = uninitialized Discovery::DependencySweep::Report
      added = slugs_registered_by { report = Discovery::DependencySweep.run(options(max_candidates: 2)) }

      report.registered.should eq(2)
      added.size.should eq(2)

      # The leftover is not lost by being bounded: it is still a lead.
      Discovery::DependencySweep.due(10).map(&.slug).should eq(["github.com/acme/third"])
    end

    it "does nothing when the graph names no repository the registry is missing" do
      report = Discovery::DependencySweep.run(options)

      report.attempted.should eq(0)
      report.registered.should eq(0)
      rendered(report).should contain("Nothing to harvest")
    end
  end

  describe ".outstanding" do
    it "counts distinct repositories the graph names and the registry lacks" do
      edge("radix", "github.com/luislavena/radix")
      edge("radix", "github.com/luislavena/radix")
      edge("ameba", "github.com/crystal-ameba/ameba")
      edge("known", "github.com/acme/known", dependent_shard: shard_at("github.com", "acme", "known"))
      edge("nameless", nil)

      Discovery::DependencySweep.outstanding.should eq(2)
    end
  end

  describe ".render" do
    it "states the cost, the bound and what is left" do
      edge("radix", "github.com/luislavena/radix")
      edge("ameba", "github.com/crystal-ameba/ameba")

      report = Discovery::DependencySweep.run(options(max_candidates: 1))
      output = rendered(report)

      output.should contain("Bound: 1 repositories this run")
      output.should contain("no host requests")
      output.should contain("registered 1 from the dependency graph")
      output.should contain("1 more repositories are named by dependencies and not yet registered")
    end

    it "names the hosts a dependency reached that the registry cannot store" do
      edge("thing", "gitea.example.com/acme/thing")

      output = rendered(Discovery::DependencySweep.run(options))

      output.should contain("on a host the registry cannot store")
      output.should contain("gitea.example.com: 1 repository")
    end
  end

  # The contract the whole feature rests on: the slug this phase reads is the
  # slug indexing writes. Proven through the real indexer and the real resolver,
  # because a spec that inserted resolved_slug itself would pass with the
  # producer wired to nothing.
  it "harvests a repository from a manifest indexing has just read" do
    consumer = shard_at("github.com", "acme", "consumer")

    manifest = <<-YAML
      name: consumer
      version: 1.0.0
      dependencies:
        radix:
          github: luislavena/radix
        router:
          gitlab: acme/router
      YAML

    recorded = RecordedGithub.new("acme/consumer")
      .repository(stars: 4, default_branch: "main")
      .tags("v1.0.0")
      .file("v1.0.0", "shard.yml", manifest)

    result = RecordedGithub.install(recorded) { ShardIndexer.index(consumer) }
    result.outcome.should eq(ShardIndexer::Outcome::Indexed)
    result.dependencies.should eq(2)

    # Indexing found neither repository, so both edges carry a null
    # dependent_shard_id and the slug that says which repository each one meant.
    version = ShardVersionQuery.new.shard_id(consumer.id).indexed_at.is_not_nil.first
    edges = DependencyQuery.new.shard_version_id(version.id).to_a
    edges.map(&.dependent_shard_id).should eq([nil, nil])
    edges.map(&.resolved_slug).compact.sort.should eq([
      "github.com/luislavena/radix",
      "gitlab.com/acme/router",
    ])

    report = uninitialized Discovery::DependencySweep::Report
    added = slugs_registered_by { report = Discovery::DependencySweep.run(options) }

    report.registered.should eq(2)
    added.should eq([
      "github.com/luislavena/radix",
      "gitlab.com/acme/router",
    ])
  end
end
