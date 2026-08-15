require "../../spec_helper"

# Required directly, like the other discovery specs: src/app.cr carries only
# version_order out of services/, because these phases exist for a Cloud Run Job
# that never boots Lucky and have no business in the web server binary.
require "../../../src/services/discovery/dependency_sweep"
require "../../../src/services/shard_indexer"

# Discovery from the dependency graph.
#
# Finding a lead touches no host, and that is a property under test as much as
# any count: the leads come out of Postgres, so a spec proving that half works
# needs no recorded HTTP at all. Reading one does touch a host, and goes through
# DependencySweep.indexer, which every spec here replaces except the end-to-end
# case. That one runs the real indexer through RecordedGithub, to prove the slug
# this phase reads is the slug indexing writes.
#
# Every spec that runs the phase MUST install an indexer. The default calls the
# real ShardIndexer, which would reach api.github.com from the suite.
private def default_indexer : Proc(Shard, ShardIndexer::Result)
  ->(shard : Shard) { ShardIndexer.index(shard) }
end

# Replaces the per-lead read with `answer` and records the slugs it was handed,
# so a spec can assert what a run actually went and read as well as its totals.
private def with_indexer(
  answer : Proc(Shard, ShardIndexer::Result),
  read : Array(String) = [] of String,
  &
)
  Discovery::DependencySweep.indexer = ->(shard : Shard) do
    read << (shard.canonical_slug || shard.name)
    answer.call(shard)
  end

  begin
    yield
  ensure
    Discovery::DependencySweep.indexer = default_indexer
  end
end

private def indexes(versions : Int32 = 1) : Proc(Shard, ShardIndexer::Result)
  ->(shard : Shard) do
    ShardIndexer::Result.new(ShardIndexer::Outcome::Indexed, shard, versions: versions)
  end
end

private def gone(detail : String = "the repository is no longer reachable") : Proc(Shard, ShardIndexer::Result)
  ->(shard : Shard) do
    ShardIndexer::Result.new(ShardIndexer::Outcome::Unavailable, shard, detail: detail)
  end
end

private def unreadable(detail : String = "502 from the host") : Proc(Shard, ShardIndexer::Result)
  ->(shard : Shard) do
    ShardIndexer::Result.new(ShardIndexer::Outcome::Failed, shard, detail: detail)
  end
end

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
    # The whole point, in one spec: a repository no crawler found, resolved
    # locally to nothing, then read from its host and stored with content.
    it "registers a repository the graph names and reads it in the same pass" do
      edge("radix", "github.com/luislavena/radix")

      read = [] of String
      report = uninitialized Discovery::DependencySweep::Report
      with_indexer(indexes(versions: 4), read) do
        report = Discovery::DependencySweep.run(options)
      end

      report.registered.should eq(1)
      report.indexed.should eq(1)
      report.versions.should eq(4)
      report.failed.should eq(0)

      # Registering and reading are one pass, not two runs apart.
      read.should eq(["github.com/luislavena/radix"])

      shard = ShardQuery.new.canonical_slug("github.com/luislavena/radix").first
      shard.name.should eq("radix")
      shard.host.should eq("github.com")
      shard.owner.should eq("luislavena")
      shard.repo.should eq("radix")
      shard.repository_url.should eq("https://github.com/luislavena/radix")
    end

    # A manifest outlives a rename, so the graph names repositories that have
    # since moved or been deleted. Reading on arrival is what turns those into
    # a row that says so, in the run that found it, rather than one that looks
    # live until something else checks.
    it "marks a lead whose repository is gone rather than leaving it looking live" do
      edge("moved", "github.com/sdogruyol/kemal")

      report = uninitialized Discovery::DependencySweep::Report
      with_indexer(gone("that owner and name no longer address a repository")) do
        report = Discovery::DependencySweep.run(options)
      end

      report.registered.should eq(1)
      report.indexed.should eq(0)
      report.unavailable.should eq(1)
      # Not a failure. A dependency on something since deleted is an ordinary
      # fact about an ecosystem, and failing the Job over one would put a red
      # mark on nearly every run.
      report.ok?.should be_true
      rendered(report).should contain("the host no longer serves")
    end

    # A host having a bad second says nothing about the lead. The row stays,
    # the reason is recorded, and IndexSweep reaches it again by staleness.
    it "keeps a lead whose host would not answer, without failing the run" do
      edge("flaky", "github.com/acme/flaky")

      report = uninitialized Discovery::DependencySweep::Report
      with_indexer(unreadable("502 from the host")) do
        report = Discovery::DependencySweep.run(options)
      end

      report.registered.should eq(1)
      report.index_failed.should eq(1)
      report.ok?.should be_true
      report.failures.first.should contain("502 from the host")
      ShardQuery.new.canonical_slug("github.com/acme/flaky").first?.should_not be_nil
    end

    # One bad lead must not cost the batch the rows already written, which is
    # the same rescue IndexSweep keeps around its own per-shard call.
    it "survives a read that raises and carries on with the rest" do
      edge("boom", "github.com/acme/aaa-boom")
      edge("fine", "github.com/acme/zzz-fine")

      exploding = ->(shard : Shard) do
        raise "socket went away" if shard.repo == "aaa-boom"
        ShardIndexer::Result.new(ShardIndexer::Outcome::Indexed, shard)
      end

      report = uninitialized Discovery::DependencySweep::Report
      with_indexer(exploding) { report = Discovery::DependencySweep.run(options) }

      report.registered.should eq(2)
      report.indexed.should eq(1)
      report.index_failed.should eq(1)
      report.failures.first.should contain("socket went away")
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
      added = [] of String
      with_indexer(indexes) do
        added = slugs_registered_by { report = Discovery::DependencySweep.run(options) }
      end

      report.registered.should eq(3)
      report.indexed.should eq(3)
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
      added = [] of String
      with_indexer(indexes) do
        added = slugs_registered_by { report = Discovery::DependencySweep.run(options) }
      end

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
      added = [] of String
      with_indexer(indexes) do
        added = slugs_registered_by { report = Discovery::DependencySweep.run(options(max_candidates: 1)) }
      end

      added.should eq(["github.com/acme/zzz"])
      report.registered.should eq(1)
    end

    # A count that can never reach zero is a count nobody can act on, so the
    # backlog figure is scoped to leads this phase can actually clear.
    it "leaves no outstanding backlog once every registrable lead is taken" do
      edge("thing", "gitea.example.com/acme/thing")
      edge("storable", "github.com/acme/storable")

      with_indexer(indexes) { Discovery::DependencySweep.run(options) }

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
      added = [] of String
      with_indexer(indexes) do
        added = slugs_registered_by { report = Discovery::DependencySweep.run(options) }
      end

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
      added = [] of String
      with_indexer(indexes) do
        added = slugs_registered_by { report = Discovery::DependencySweep.run(options(max_candidates: 2)) }
      end

      report.registered.should eq(2)
      added.size.should eq(2)

      # The leftover is not lost by being bounded: it is still a lead.
      Discovery::DependencySweep.due(10).map(&.slug).should eq(["github.com/acme/third"])
    end

    # No leads means no reads. The indexer is installed anyway, so that a
    # regression which started reading something would reach a fake rather than
    # api.github.com from the suite.
    it "does nothing when the graph names no repository the registry is missing" do
      read = [] of String
      report = uninitialized Discovery::DependencySweep::Report
      with_indexer(indexes, read) { report = Discovery::DependencySweep.run(options) }

      report.attempted.should eq(0)
      report.registered.should eq(0)
      read.should be_empty
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
    it "states the bound, where the leads come from and what is left" do
      edge("radix", "github.com/luislavena/radix")
      edge("ameba", "github.com/crystal-ameba/ameba")

      report = uninitialized Discovery::DependencySweep::Report
      with_indexer(indexes) { report = Discovery::DependencySweep.run(options(max_candidates: 1)) }
      output = rendered(report)

      output.should contain("Bound: 1 repositories this run")
      output.should contain("costs no host requests")
      output.should contain("registered 1 from the dependency graph, indexed 1")
      output.should contain("1 more repositories are named by dependencies and not yet registered")
    end

    it "names the hosts a dependency reached that the registry cannot store" do
      edge("thing", "gitea.example.com/acme/thing")

      report = uninitialized Discovery::DependencySweep::Report
      with_indexer(indexes) { report = Discovery::DependencySweep.run(options) }
      output = rendered(report)

      output.should contain("on a host the registry cannot store")
      output.should contain("gitea.example.com: 1 repository")
    end
  end

  # The contract the whole feature rests on, driven end to end with no seams
  # except the recorded transport: index a shard, have its manifest name a
  # repository the registry has never seen, and come out the other side with
  # that repository stored and carrying its own content.
  #
  # The real indexer and the real resolver on both halves, because a spec that
  # inserted resolved_slug itself would pass with the producer wired to nothing,
  # and one that faked the read would pass with the consumer wired to nothing.
  it "reads a repository a manifest named and the registry had never seen" do
    consumer = shard_at("github.com", "acme", "consumer")

    manifest = <<-YAML
      name: consumer
      version: 1.0.0
      dependencies:
        radix:
          github: luislavena/radix
      YAML

    # radix as GitHub would answer for it, under the name the manifest does NOT
    # use. The row is created from the dependency key and then replaced by what
    # the repository says about itself, so the description proves the read
    # happened rather than the registration.
    recorded = {
      "acme/consumer" => RecordedGithub.new("acme/consumer")
        .repository(stars: 4, default_branch: "main")
        .tags("v1.0.0")
        .file("v1.0.0", "shard.yml", manifest),
      "luislavena/radix" => RecordedGithub.new("luislavena/radix")
        .repository(stars: 300, description: "Radix tree implementation", default_branch: "master")
        .tags("v0.4.1")
        .file("v0.4.1", "shard.yml", "name: radix\nversion: 0.4.1\nlicense: MIT\n"),
    }

    RecordedGithub.install(recorded) do
      result = ShardIndexer.index(consumer)
      result.outcome.should eq(ShardIndexer::Outcome::Indexed)
      result.dependencies.should eq(1)

      # Indexing found no row for radix, so the edge carries a null
      # dependent_shard_id and the slug naming which repository it meant.
      version = ShardVersionQuery.new.shard_id(consumer.id).indexed_at.is_not_nil.first
      edge = DependencyQuery.new.shard_version_id(version.id).first
      edge.dependent_shard_id.should be_nil
      edge.resolved_slug.should eq("github.com/luislavena/radix")

      report = Discovery::DependencySweep.run(options)
      report.registered.should eq(1)
      report.indexed.should eq(1)
    end

    # Stored, and stored with the repository's own facts rather than an
    # identity and the dependency key.
    radix = ShardQuery.new.canonical_slug("github.com/luislavena/radix").first
    radix.indexed_at.should_not be_nil
    radix.github_stars.should eq(300)
    radix.description.should eq("Radix tree implementation")
    radix.license.should eq("MIT")
    radix.latest_version.should eq("0.4.1")
  end
end
