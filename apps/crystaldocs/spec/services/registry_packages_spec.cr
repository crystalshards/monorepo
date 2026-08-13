require "../spec_helper"

private def release(version : String, yanked : Bool = false, day : Int32 = 1)
  CrystalDocs::RegistryPackages::Release.new(version, Time.utc(2024, 1, day), yanked)
end

# Which release a reader gets when they ask for a package without naming one.
describe CrystalDocs::RegistryPackages do
  describe ".default_release" do
    it "picks by precedence, not by string order" do
      chosen = CrystalDocs::RegistryPackages.default_release([
        release("1.9.0", day: 1),
        release("1.10.0", day: 2),
      ])

      chosen.try(&.version).should eq("1.10.0")
    end

    # Publication order is not precedence order: a patch to an old series is
    # tagged after the release it does not supersede.
    it "ignores which release was published most recently" do
      chosen = CrystalDocs::RegistryPackages.default_release([
        release("2.0.0", day: 1),
        release("1.9.1", day: 2),
      ])

      chosen.try(&.version).should eq("2.0.0")
    end

    it "prefers a release over its own prereleases" do
      chosen = CrystalDocs::RegistryPackages.default_release([
        release("1.0.0-rc1"),
        release("1.0.0"),
      ])

      chosen.try(&.version).should eq("1.0.0")
    end

    it "never lands on a withdrawn release" do
      chosen = CrystalDocs::RegistryPackages.default_release([
        release("1.0.0"),
        release("2.0.0", yanked: true),
      ])

      chosen.try(&.version).should eq("1.0.0")
    end

    # The registry has said not to use it. A default that contradicts that is
    # worse than no default, and the version is still reachable by name.
    it "has no default when every release is withdrawn" do
      chosen = CrystalDocs::RegistryPackages.default_release([
        release("1.0.0", yanked: true),
        release("2.0.0", yanked: true),
      ])

      chosen.should be_nil
    end

    it "has no default when there are no releases" do
      CrystalDocs::RegistryPackages.default_release([] of CrystalDocs::RegistryPackages::Release)
        .should be_nil
    end

    # Deterministic rather than arbitrary: the reader gets the same answer
    # twice running even when nothing parses.
    it "falls back to the last release when no version is a version" do
      chosen = CrystalDocs::RegistryPackages.default_release([
        release("nightly", day: 1),
        release("edge", day: 2),
      ])

      chosen.try(&.version).should eq("edge")
    end

    # Semver ranks 2.0.0-rc1 above 1.9.0, so "highest version" alone sent
    # every reader of a shard mid-release-candidate to an API that has not
    # shipped. It is also what `shards.latest_version` says, and the browse
    # card shows that column, so the badge and the page it links to would
    # disagree.
    it "stays on the stable release when a newer prerelease exists" do
      chosen = CrystalDocs::RegistryPackages.default_release([
        release("1.9.0", day: 1),
        release("2.0.0-rc1", day: 2),
      ])

      chosen.try(&.version).should eq("1.9.0")
    end

    it "takes the highest prerelease when nothing stable was ever tagged" do
      chosen = CrystalDocs::RegistryPackages.default_release([
        release("2.0.0-rc1", day: 1),
        release("2.0.0-rc2", day: 2),
      ])

      chosen.try(&.version).should eq("2.0.0-rc2")
    end

    # An unrankable tag ranks below a real prerelease rather than beside a
    # stable one. Treating "nightly" as stable because it does not parse would
    # let it beat a genuine 2.0.0-rc1.
    it "prefers a prerelease over a tag that is not a version" do
      chosen = CrystalDocs::RegistryPackages.default_release([
        release("2.0.0-rc1", day: 1),
        release("nightly", day: 2),
      ])

      chosen.try(&.version).should eq("2.0.0-rc1")
    end

    it "prefers a stable release over a tag that is not a version" do
      chosen = CrystalDocs::RegistryPackages.default_release([
        release("1.9.0", day: 1),
        release("nightly", day: 2),
      ])

      chosen.try(&.version).should eq("1.9.0")
    end
  end

  # A registry nobody configured cannot tell a real shard from an invented one,
  # and the two failures it must not produce are 404ing documentation this app
  # holds, and registering rows for anything anyone types. Both come from
  # reading "we could not ask" as "there is no such package".
  describe "#find without a registry" do
    it "reports that it could not answer, rather than that there is no package" do
      configured = RegistryDatabase.configured?
      RegistryDatabase.configured = false

      begin
        lookup = CrystalDocs::RegistryPackages.new.find("github.com/kemalcr/kemal")

        lookup.package.should be_nil
        lookup.registry_answered?.should be_false
      ensure
        RegistryDatabase.configured = configured
      end
    end

    it "resolves no name, so a bare URL falls back to this app's own rows" do
      configured = RegistryDatabase.configured?
      RegistryDatabase.configured = false

      begin
        CrystalDocs::RegistryPackages.new.slugs_for("kemal").should be_empty
      ensure
        RegistryDatabase.configured = configured
      end
    end
  end

  # Which release a dependency requirement resolves to when the cascade
  # commissions that dependency's documentation. The answer has to be the same
  # one `shards install` would have produced, because that is the release the
  # parent's own documentation was built against.
  describe ".best_version" do
    requirement = ->(raw : String) {
      CrystalDocs::Semver::Requirement.parse?(raw).not_nil!
    }

    it "takes the highest release the requirement admits" do
      chosen = CrystalDocs::RegistryPackages.best_version(
        ["0.4.0", "0.4.1", "0.5.0"],
        requirement.call("~> 0.4.0")
      )

      chosen.should eq("0.4.1")
    end

    it "orders by precedence rather than by string" do
      chosen = CrystalDocs::RegistryPackages.best_version(
        ["1.9.0", "1.10.0"],
        requirement.call(">= 1.0.0")
      )

      chosen.should eq("1.10.0")
    end

    # The string is the tag a build clones and the segment a URL carries, so
    # returning a reparsed version would commission "1.2.0" for a repository
    # whose tag is "v1.2".
    it "returns the string the registry holds, not a normalised one" do
      chosen = CrystalDocs::RegistryPackages.best_version(
        ["v1.2"],
        requirement.call(">= 1.0.0")
      )

      chosen.should eq("v1.2")
    end

    it "refuses a prerelease unless the requirement asked for one" do
      chosen = CrystalDocs::RegistryPackages.best_version(
        ["1.0.0", "2.0.0-rc1"],
        requirement.call(">= 1.0.0")
      )

      chosen.should eq("1.0.0")
    end

    # Nil is a real answer and never means "take the newest instead": building
    # a release the parent excluded documents an API that reader never had.
    it "answers nothing when no release satisfies" do
      chosen = CrystalDocs::RegistryPackages.best_version(
        ["2.0.0"],
        requirement.call("~> 1.2.0")
      )

      chosen.should be_nil
    end

    it "skips a tag that is not a version at all" do
      chosen = CrystalDocs::RegistryPackages.best_version(
        ["nightly", "1.0.0"],
        requirement.call(">= 1.0.0")
      )

      chosen.should eq("1.0.0")
    end
  end
end
