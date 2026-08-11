require "../spec_helper"

private def version(raw : String) : CrystalDocs::Semver::Version
  parsed = CrystalDocs::Semver::Version.parse?(raw)
  raise "#{raw.inspect} did not parse as a version" unless parsed
  parsed
end

private def requirement(raw : String) : CrystalDocs::Semver::Requirement
  parsed = CrystalDocs::Semver::Requirement.parse?(raw)
  raise "#{raw.inspect} did not parse as a requirement" unless parsed
  parsed
end

private def satisfied?(requirement_text : String, version_text : String) : Bool
  requirement(requirement_text).satisfied_by?(version(version_text))
end

describe CrystalDocs::Semver::Version do
  describe "ordering" do
    it "compares segments as numbers, not as text" do
      # The whole reason this exists. Lexically "1.10.0" sorts before "1.9.0",
      # so anything comparing version strings sends a reader on 1.10 to the
      # 1.9 documentation.
      version("1.10.0").should be > version("1.9.0")
      version("1.9.0").should be < version("1.10.0")

      ["1.9.0", "1.10.0", "1.2.0"].map { |raw| version(raw) }.max
        .should eq(version("1.10.0"))
    end

    it "ranks a prerelease below the release it leads to" do
      version("1.0.0-rc1").should be < version("1.0.0")
      version("1.0.0").should be > version("1.0.0-rc1")
    end

    it "orders prerelease identifiers, numerically where both are numeric" do
      version("1.0.0-rc.2").should be > version("1.0.0-rc.1")
      version("1.0.0-rc.10").should be > version("1.0.0-rc.9")
      # A numeric identifier ranks below an alphanumeric one.
      version("1.0.0-1").should be < version("1.0.0-alpha")
      # More identifiers wins when the shared prefix is equal.
      version("1.0.0-rc.1").should be > version("1.0.0-rc")
    end

    it "ignores build metadata, which carries no precedence" do
      version("1.2.3+20260811").should eq(version("1.2.3"))
    end

    it "fills in segments that were left off" do
      version("1.2").should eq(version("1.2.0"))
      version("1").should eq(version("1.0.0"))
    end

    it "accepts a v prefix, which shards and tags both use" do
      version("v1.2.3").should eq(version("1.2.3"))
    end
  end

  describe ".parse?" do
    it "returns nil for anything that is not a version" do
      CrystalDocs::Semver::Version.parse?(nil).should be_nil
      CrystalDocs::Semver::Version.parse?("").should be_nil
      CrystalDocs::Semver::Version.parse?("latest").should be_nil
      CrystalDocs::Semver::Version.parse?("1.x").should be_nil
      CrystalDocs::Semver::Version.parse?("1.2.3.4").should be_nil
    end
  end
end

describe CrystalDocs::Semver::Requirement do
  describe "~>" do
    it "allows patch releases when written to patch precision" do
      satisfied?("~> 1.2.3", "1.2.3").should be_true
      satisfied?("~> 1.2.3", "1.2.9").should be_true
      # 1.3.0 is the exclusive ceiling: drop the last segment, raise the one
      # that is now last.
      satisfied?("~> 1.2.3", "1.3.0").should be_false
      satisfied?("~> 1.2.3", "1.2.2").should be_false
    end

    it "allows minor releases when written to minor precision" do
      satisfied?("~> 1.2", "1.2.0").should be_true
      satisfied?("~> 1.2", "1.9.0").should be_true
      satisfied?("~> 1.2", "1.10.0").should be_true
      satisfied?("~> 1.2", "2.0.0").should be_false
      satisfied?("~> 1.2", "1.1.0").should be_false
    end

    it "allows the whole major series when written to major precision" do
      satisfied?("~> 1", "1.7.3").should be_true
      satisfied?("~> 1", "2.0.0").should be_false
    end
  end

  describe "comparison operators" do
    it "honours each one" do
      satisfied?(">= 1.9.0", "1.10.0").should be_true
      satisfied?(">= 1.9.0", "1.8.0").should be_false
      satisfied?("<= 1.9.0", "1.9.0").should be_true
      satisfied?("<= 1.9.0", "1.10.0").should be_false
      satisfied?("> 1.9.0", "1.10.0").should be_true
      satisfied?("> 1.9.0", "1.9.0").should be_false
      satisfied?("< 1.10.0", "1.9.0").should be_true
      satisfied?("< 1.10.0", "1.10.0").should be_false
      satisfied?("= 1.9.0", "1.9.0").should be_true
      satisfied?("= 1.9.0", "1.9.1").should be_false
    end

    it "reads a bare version as an exact pin" do
      # The registry stores a `crystal:` key written without an operator
      # exactly as the author typed it, so this form is real data.
      satisfied?("1.9.0", "1.9.0").should be_true
      satisfied?("1.9.0", "1.10.0").should be_false
    end

    it "reads >= as one operator rather than > followed by =" do
      satisfied?(">= 1.9.0", "1.9.0").should be_true
    end

    it "requires every clause of a comma separated range" do
      satisfied?(">= 2.0, < 3.0", "2.5.0").should be_true
      satisfied?(">= 2.0, < 3.0", "3.0.0").should be_false
      satisfied?(">= 2.0, < 3.0", "1.9.0").should be_false
    end
  end

  describe "prereleases" do
    it "does not offer a prerelease to a requirement that asked for a release" do
      # 1.3.0-rc1 sorts below 1.3.0 and so falls inside "~> 1.2", but an rc is
      # not a release and linking to it documents an API that has not shipped.
      satisfied?("~> 1.2", "1.3.0-rc1").should be_false
      satisfied?(">= 1.0.0", "2.0.0-rc1").should be_false
    end

    it "offers one when the requirement names a prerelease" do
      satisfied?(">= 1.0.0-rc1", "1.0.0-rc2").should be_true
      satisfied?("1.0.0-rc1", "1.0.0-rc1").should be_true
    end
  end

  describe ".parse?" do
    it "treats an explicit star as any release" do
      # Shards records a dependency with no version key as "*", which is a
      # statement rather than an absence.
      satisfied?("*", "1.2.3").should be_true
    end

    it "fails closed on absent or unreadable metadata" do
      # Absent is not permissive. These all leave the name plain text rather
      # than matching everything.
      CrystalDocs::Semver::Requirement.parse?(nil).should be_nil
      CrystalDocs::Semver::Requirement.parse?("").should be_nil
      CrystalDocs::Semver::Requirement.parse?("   ").should be_nil
      CrystalDocs::Semver::Requirement.parse?("latest").should be_nil
      CrystalDocs::Semver::Requirement.parse?(">= ").should be_nil
      CrystalDocs::Semver::Requirement.parse?(">= 1.0, garbage").should be_nil
    end
  end

  describe "#best" do
    it "picks the highest satisfying version, comparing numerically" do
      candidates = ["1.9.0", "1.10.0", "1.2.0"].map { |raw| version(raw) }

      requirement("~> 1.2").best(candidates).should eq(version("1.10.0"))
    end

    it "picks the highest version inside the range, not the highest overall" do
      candidates = ["1.2.0", "1.2.9", "1.3.0", "2.0.0"].map { |raw| version(raw) }

      requirement("~> 1.2.0").best(candidates).should eq(version("1.2.9"))
    end

    it "returns nil when nothing satisfies, rather than the newest" do
      candidates = ["2.0.0", "3.0.0"].map { |raw| version(raw) }

      requirement("~> 1.2").best(candidates).should be_nil
      requirement("~> 1.2").best([] of CrystalDocs::Semver::Version).should be_nil
    end
  end
end
