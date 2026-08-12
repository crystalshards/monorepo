require "../spec_helper"

# Which version is "latest", for refs a host just returned and for rows already
# stored.
#
# Every case here is a way of getting this wrong that produces no error: the
# page, the card, the API payload and `shards.latest_version` each name a
# version, and a reader only ever sees that they disagree.
private def tag(name : String, committed_at : Time? = nil) : RepositorySnapshot::Ref
  RepositorySnapshot::Ref.from_tag(name, commit_sha: "sha-#{name}", committed_at: committed_at)
end

private def branch(name : String) : RepositorySnapshot::Ref
  RepositorySnapshot::Ref.from_branch(name)
end

private def names(refs : Array(RepositorySnapshot::Ref)) : Array(String)
  refs.map(&.ref)
end

private def stored(
  shard : Shard,
  version : String,
  released_at : Time = Time.utc,
  source : String = ShardVersion::Source::TAG,
) : ShardVersion
  ShardVersionFactory.create &.shard_id(shard.id)
    .version(version)
    .released_at(released_at)
    .source(source)
end

describe VersionOrder do
  describe "picking the latest tag" do
    it "picks the highest semver, not the first the host returned" do
      # GitHub does not document /tags as reverse-chronological and a retagged
      # release moves. Trusting the response order is how a shard defaults to
      # whichever version the host happened to list first.
      refs = [tag("v1.9.0"), tag("v1.12.0"), tag("v1.11.0")]

      VersionOrder.latest(refs).not_nil!.version.should eq("1.12.0")
    end

    it "picks the highest semver, not the newest date" do
      # Measured on kemal: the tag list carries no dates, so 64 of 65 rows get
      # the repository's pushed_at and the one indexed version gets a real
      # commit date. A date sort therefore ranks by an artefact of indexing.
      old = Time.utc(2019, 1, 1)
      new = Time.utc(2026, 1, 1)
      refs = [tag("v1.12.0", committed_at: old), tag("v1.9.0", committed_at: new)]

      VersionOrder.latest(refs).not_nil!.version.should eq("1.12.0")
    end

    it "picks the highest semver, not the last tag in the list" do
      refs = [tag("v2.0.0"), tag("v1.0.0")]

      VersionOrder.latest(refs).not_nil!.version.should eq("2.0.0")
    end

    it "compares numerically rather than as strings" do
      # The string comparison that "works" until a project reaches version 10.
      refs = [tag("v9.0.0"), tag("v10.0.0")]

      VersionOrder.latest(refs).not_nil!.version.should eq("10.0.0")
    end

    it "treats a missing component as zero, so 1.2 and 1.2.0 are one version" do
      VersionOrder.latest([tag("1.2"), tag("1.2.0")]).not_nil!.ref.should eq("1.2")
      VersionOrder.latest([tag("1.2"), tag("1.2.1")]).not_nil!.ref.should eq("1.2.1")
    end
  end

  describe "prereleases" do
    it "does not let a prerelease outrank a release" do
      # A shard whose newest tag is 2.0.0-rc1 still defaults to 1.9.0: telling a
      # reader to depend on a release candidate is worse than telling them about
      # a slightly older release.
      refs = [tag("v2.0.0-rc1"), tag("v1.9.0")]

      VersionOrder.latest(refs).not_nil!.version.should eq("1.9.0")
    end

    it "prefers the release over its own prerelease" do
      refs = [tag("v1.0.0-rc1"), tag("v1.0.0")]

      VersionOrder.latest(refs).not_nil!.version.should eq("1.0.0")
      VersionOrder.stable?(tag("v1.0.0")).should be_true
      VersionOrder.stable?(tag("v1.0.0-rc1")).should be_false
    end

    it "falls back to the highest prerelease when nothing was ever released" do
      refs = [tag("v0.1.0-alpha.1"), tag("v0.1.0-alpha.2")]

      VersionOrder.latest(refs).not_nil!.version.should eq("0.1.0-alpha.2")
    end

    it "orders prerelease identifiers by semver's rules, not alphabetically" do
      # Numeric identifiers compare numerically and rank below alphanumeric
      # ones, so alpha.9 is older than alpha.10 and rc is newer than both.
      ordered = names(VersionOrder.sort([
        tag("v1.0.0-alpha.9"),
        tag("v1.0.0-rc"),
        tag("v1.0.0-alpha.10"),
      ]))

      ordered.should eq(["v1.0.0-rc", "v1.0.0-alpha.10", "v1.0.0-alpha.9"])
    end
  end

  describe "a repository with no tags" do
    it "falls back to the default branch rather than having no version" do
      # A branch row is what gives an untagged shard a page, a manifest and
      # dependency edges instead of reading as a shard with no versions.
      latest = VersionOrder.latest([branch("master")]).not_nil!

      latest.ref.should eq("master")
      latest.tag?.should be_false
    end

    it "prefers any tag over the branch when both are present" do
      # The branch ref only exists when there are no tags, but the rule has to
      # hold anyway: a page must never default to "master" with a version badge.
      latest = VersionOrder.latest([branch("main"), tag("v0.1.0")]).not_nil!

      latest.ref.should eq("v0.1.0")
      latest.tag?.should be_true
    end

    it "has no latest when the host returned nothing at all" do
      VersionOrder.latest([] of RepositorySnapshot::Ref).should be_nil
    end
  end

  describe "tags that are not versions" do
    it "does not crash on junk tag names" do
      refs = [tag("nightly"), tag("v1.0.0"), tag("latest"), tag("release-2024-01-01")]

      VersionOrder.latest(refs).not_nil!.version.should eq("1.0.0")
    end

    it "sorts every unparseable tag below every version" do
      ordered = names(VersionOrder.sort([tag("nightly"), tag("v1.0.0"), tag("latest")]))

      ordered.should eq(["v1.0.0", "nightly", "latest"])
    end

    it "keeps unparseable tags in input order, so the result is stable" do
      # Two runs over the same list must choose the same latest. Without a tie
      # break the sort is free to swap equal elements and a shard's default
      # version would change on reindex with nothing having changed upstream.
      refs = [tag("nightly"), tag("latest"), tag("edge")]

      names(VersionOrder.sort(refs)).should eq(["nightly", "latest", "edge"])
      names(VersionOrder.sort(refs)).should eq(names(VersionOrder.sort(refs)))
    end

    it "still answers when every tag is junk" do
      latest = VersionOrder.latest([tag("nightly"), tag("latest")]).not_nil!

      # No release exists, so the first in input order stands in. The important
      # part is that a page gets a version rather than nil.
      latest.ref.should eq("nightly")
      VersionOrder.stable?(latest).should be_false
    end

    it "does not read a date-stamped name as a version" do
      VersionOrder.parse("release-2024-01-01").should be_nil
      VersionOrder.parse("nightly").should be_nil
      VersionOrder.parse("").should be_nil
    end

    it "accepts the spellings tags actually use" do
      VersionOrder.parse("v1.2.3").not_nil!.numbers.should eq([1, 2, 3])
      VersionOrder.parse("V1.2.3").not_nil!.numbers.should eq([1, 2, 3])
      VersionOrder.parse("1.2.3").not_nil!.numbers.should eq([1, 2, 3])
      VersionOrder.parse(" 1.2.3 ").not_nil!.numbers.should eq([1, 2, 3])
      VersionOrder.parse("1.2.3+build.5").not_nil!.prerelease.should be_empty
      VersionOrder.parse("1.2.3-rc.1").not_nil!.prerelease.should eq(["rc", "1"])
    end
  end

  describe "ordering rows already in the database" do
    it "orders stored versions by semver rather than by released_at" do
      # The regression this exists to stop: the card, the page and the API
      # payload all ordered by released_at, which on a freshly indexed shard is
      # the repository's pushed_at for every row but one.
      shard = ShardFactory.create
      same_instant = Time.utc(2024, 6, 1)

      stored(shard, "1.9.0", released_at: same_instant)
      stored(shard, "1.12.0", released_at: same_instant)
      stored(shard, "1.11.0", released_at: same_instant)

      rows = ShardVersionQuery.new.shard_id(shard.id).to_a

      VersionOrder.sort_versions(rows).map(&.version)
        .should eq(["1.12.0", "1.11.0", "1.9.0"])
    end

    it "picks the same latest a page's shards.latest_version column claims" do
      shard = ShardFactory.create
      stored(shard, "1.9.0", released_at: Time.utc(2026, 1, 1))
      stored(shard, "1.12.0", released_at: Time.utc(2019, 1, 1))

      rows = ShardVersionQuery.new.shard_id(shard.id).to_a

      # Dated the wrong way round on purpose: the newest row by date is 1.9.0.
      VersionOrder.latest_version(rows).not_nil!.version.should eq("1.12.0")
    end

    it "does not default a page to a prerelease row" do
      shard = ShardFactory.create
      stored(shard, "1.9.0")
      stored(shard, "2.0.0-rc1")

      rows = ShardVersionQuery.new.shard_id(shard.id).to_a

      VersionOrder.latest_version(rows).not_nil!.version.should eq("1.9.0")
    end

    it "prefers a tagged release over a branch row" do
      shard = ShardFactory.create
      stored(shard, "master", source: ShardVersion::Source::BRANCH)
      stored(shard, "0.1.0")

      rows = ShardVersionQuery.new.shard_id(shard.id).to_a
      latest = VersionOrder.latest_version(rows).not_nil!

      latest.version.should eq("0.1.0")
      latest.release?.should be_true
    end

    it "falls back to the branch row when that is all there is" do
      shard = ShardFactory.create
      stored(shard, "main", source: ShardVersion::Source::BRANCH)

      rows = ShardVersionQuery.new.shard_id(shard.id).to_a
      latest = VersionOrder.latest_version(rows).not_nil!

      latest.version.should eq("main")
      latest.release?.should be_false
    end

    it "has no latest row for a shard with no versions" do
      VersionOrder.latest_version([] of ShardVersion).should be_nil
    end
  end
end
