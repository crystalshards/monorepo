require "../spec_helper"

# The statements, run.
#
# Everything asked of this class is addressed by `docs.package_name`, and for
# every row the registry route creates that is a canonical slug. Matching
# `shards.name` instead answered nil for all of them, which made
# `DependencyIndex` return an empty index at its first guard, which made every
# type name on every documentation page plain text. None of that is visible to
# a fake registry, so these examples run the real SQL.
describe CrystalDocs::RegistryMetadata do
  describe "#source" do
    it "resolves a package addressed by its canonical slug" do
      RegistrySchema.reset
      kemal = RegistrySchema.shard("kemal", "github.com/kemalcr/kemal")
      RegistrySchema.version(kemal, "1.12.0", ">= 1.12.0")

      source = CrystalDocs::RegistryMetadata.new.source("github.com/kemalcr/kemal", "1.12.0")

      source.should_not be_nil
      source.try(&.crystal_requirement).should eq(">= 1.12.0")
    end

    it "resolves a package addressed by a bare name" do
      RegistrySchema.reset
      legacy = RegistrySchema.shard("kemal", nil)
      RegistrySchema.version(legacy, "1.6.0", ">= 1.0.0")

      source = CrystalDocs::RegistryMetadata.new.source("kemal", "1.6.0")

      source.try(&.crystal_requirement).should eq(">= 1.0.0")
    end

    it "tells a version that declared no Crystal from one that does not exist" do
      RegistrySchema.reset
      kemal = RegistrySchema.shard("kemal", "github.com/kemalcr/kemal")
      RegistrySchema.version(kemal, "1.12.0", nil)

      metadata = CrystalDocs::RegistryMetadata.new

      declared = metadata.source("github.com/kemalcr/kemal", "1.12.0")
      declared.should_not be_nil
      declared.try(&.crystal_requirement).should be_nil

      metadata.source("github.com/kemalcr/kemal", "9.9.9").should be_nil
    end

    # `shards.name` carries no unique index and 28 of the registry's 829 rows
    # share a name with another. Picking the first would hand a reader
    # somebody else's dependency set.
    it "refuses to answer when a bare name names two repositories" do
      RegistrySchema.reset
      first = RegistrySchema.shard("lsp", "github.com/TunkShif/lsp.cr")
      second = RegistrySchema.shard("lsp", "github.com/elbywan/lsp.cr")
      RegistrySchema.version(first, "1.0.0", ">= 1.0.0")
      RegistrySchema.version(second, "1.0.0", ">= 1.0.0")

      metadata = CrystalDocs::RegistryMetadata.new

      metadata.source("lsp", "1.0.0").should be_nil
      # Each repository still answers for itself, because a slug is an answer
      # where a shared name is a question.
      metadata.source("github.com/TunkShif/lsp.cr", "1.0.0").should_not be_nil
      metadata.source("github.com/elbywan/lsp.cr", "1.0.0").should_not be_nil
    end

    it "answers a dependency by the key this app documents it under" do
      RegistrySchema.reset
      kemal = RegistrySchema.shard("kemal", "github.com/kemalcr/kemal")
      radix = RegistrySchema.shard("radix", "github.com/luislavena/radix")
      release = RegistrySchema.version(kemal, "1.12.0", ">= 1.12.0")
      RegistrySchema.dependency(release, "radix", "~> 0.4.0", resolved_shard_id: radix)

      source = CrystalDocs::RegistryMetadata.new.source("github.com/kemalcr/kemal", "1.12.0")

      # The slug, not "radix". The docs row is keyed by slug, so the name the
      # registry recorded would join against nothing.
      source.try(&.dependencies.map(&.key)).should eq(["github.com/luislavena/radix"])
      source.try(&.dependencies.first.requirement).should eq("~> 0.4.0")
    end

    it "falls back to the shard.yml key when the registry resolved nothing" do
      RegistrySchema.reset
      kemal = RegistrySchema.shard("kemal", "github.com/kemalcr/kemal")
      release = RegistrySchema.version(kemal, "1.12.0", ">= 1.12.0")
      RegistrySchema.dependency(release, "private_thing", "~> 1.0")

      source = CrystalDocs::RegistryMetadata.new.source("github.com/kemalcr/kemal", "1.12.0")

      source.try(&.dependencies.map(&.key)).should eq(["private_thing"])
    end

    it "reads a repository's own dependencies and not another's" do
      RegistrySchema.reset
      kemal = RegistrySchema.shard("kemal", "github.com/kemalcr/kemal")
      other = RegistrySchema.shard("kemal", "github.com/someone/kemal")
      mine = RegistrySchema.version(kemal, "1.12.0", ">= 1.12.0")
      theirs = RegistrySchema.version(other, "1.12.0", ">= 1.12.0")
      RegistrySchema.dependency(mine, "radix", "~> 0.4.0")
      RegistrySchema.dependency(theirs, "wrong", "~> 9.0")

      source = CrystalDocs::RegistryMetadata.new.source("github.com/kemalcr/kemal", "1.12.0")

      source.try(&.dependencies.map(&.key)).should eq(["radix"])
    end

    # A published API can only mention types from what it links against at
    # runtime, so a linter in the dependency list is not a source of names.
    it "leaves development dependencies out" do
      RegistrySchema.reset
      kemal = RegistrySchema.shard("kemal", "github.com/kemalcr/kemal")
      release = RegistrySchema.version(kemal, "1.12.0", ">= 1.12.0")
      RegistrySchema.dependency(release, "radix", "~> 0.4.0")
      RegistrySchema.dependency(release, "ameba", "~> 1.6", scope: "development")

      source = CrystalDocs::RegistryMetadata.new.source("github.com/kemalcr/kemal", "1.12.0")

      source.try(&.dependencies.map(&.key)).should eq(["radix"])
    end
  end

  describe "#published_versions" do
    it "answers in the key shape it was asked in" do
      RegistrySchema.reset
      radix = RegistrySchema.shard("radix", "github.com/luislavena/radix")
      RegistrySchema.version(radix, "0.4.0", ">= 1.0.0")
      RegistrySchema.version(radix, "0.4.1", ">= 1.0.0")

      published = CrystalDocs::RegistryMetadata.new
        .published_versions(["github.com/luislavena/radix"])

      published["github.com/luislavena/radix"].map(&.version).sort!
        .should eq(["0.4.0", "0.4.1"])
      # Never under the shard's own name, which is not a key this app can
      # address a page by.
      published["radix"]?.should be_nil
    end

    it "matches a bare name only for a repository that has no slug" do
      RegistrySchema.reset
      slugged = RegistrySchema.shard("radix", "github.com/luislavena/radix")
      legacy = RegistrySchema.shard("granite", nil)
      RegistrySchema.version(slugged, "0.4.0", ">= 1.0.0")
      RegistrySchema.version(legacy, "0.23.4", ">= 1.0.0")

      published = CrystalDocs::RegistryMetadata.new
        .published_versions(["radix", "granite"])

      published["radix"]?.should be_nil
      published["granite"].map(&.version).should eq(["0.23.4"])
    end

    it "leaves out withdrawn releases, because a link is a recommendation" do
      RegistrySchema.reset
      radix = RegistrySchema.shard("radix", "github.com/luislavena/radix")
      RegistrySchema.version(radix, "0.4.0", ">= 1.0.0")
      RegistrySchema.version(radix, "0.4.1", ">= 1.0.0", yanked: true)

      published = CrystalDocs::RegistryMetadata.new
        .published_versions(["github.com/luislavena/radix"])

      published["github.com/luislavena/radix"].map(&.version).should eq(["0.4.0"])
    end

    it "carries the Crystal each release declared, including none" do
      RegistrySchema.reset
      radix = RegistrySchema.shard("radix", "github.com/luislavena/radix")
      RegistrySchema.version(radix, "0.4.0", ">= 1.0.0")
      RegistrySchema.version(radix, "0.4.1", nil)

      published = CrystalDocs::RegistryMetadata.new
        .published_versions(["github.com/luislavena/radix"])
        .fetch("github.com/luislavena/radix", [] of CrystalDocs::RegistryMetadata::PublishedVersion)
        .to_h { |version| {version.version, version.crystal_requirement} }

      published["0.4.0"].should eq(">= 1.0.0")
      published["0.4.1"].should be_nil
    end

    it "asks nothing of the registry when there is nothing to ask about" do
      RegistrySchema.reset

      CrystalDocs::RegistryMetadata.new
        .published_versions([] of String)
        .should be_empty
    end
  end
end
