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
end
