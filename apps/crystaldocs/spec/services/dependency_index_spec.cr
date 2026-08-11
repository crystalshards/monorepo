require "../spec_helper"

# Stands in for the crystalshards registry, so these specs exercise the
# selection rules rather than a second database. The real reader is guarded by
# `RegistryDatabase.configured?` and is the only thing that talks to it.
private class FakeRegistry < CrystalDocs::RegistryMetadata
  def initialize(
    @declared : CrystalDocs::RegistryMetadata::SourceVersion?,
    @published : Hash(String, Array(CrystalDocs::RegistryMetadata::PublishedVersion)),
  )
  end

  def source(package_name : String, version : String) : CrystalDocs::RegistryMetadata::SourceVersion?
    @declared
  end

  def published_versions(package_names : Array(String)) : Hash(String, Array(CrystalDocs::RegistryMetadata::PublishedVersion))
    @published
  end
end

private class FakeLoader < CrystalDocs::DocsLoader
  def initialize(@documents : Hash(String, String))
    super()
  end

  def load(package_name : String, version : String) : CrystalDocs::DocsLoader::Result
    raw = @documents["#{package_name}/#{version}"]?
    return CrystalDocs::DocsLoader::Result.new(document: nil, store_answered: false) unless raw

    CrystalDocs::DocsLoader::Result.new(
      document: CrystalDocs::DocsDocument.parse(raw),
      store_answered: true
    )
  end
end

private def published(version : String, crystal : String?) : CrystalDocs::RegistryMetadata::PublishedVersion
  CrystalDocs::RegistryMetadata::PublishedVersion.new(version, crystal)
end

private def declares(crystal : String?, dependencies : Hash(String, String)) : CrystalDocs::RegistryMetadata::SourceVersion
  CrystalDocs::RegistryMetadata::SourceVersion.new(
    crystal_requirement: crystal,
    dependencies: dependencies.map do |name, requirement|
      CrystalDocs::RegistryMetadata::DeclaredDependency.new(name, requirement)
    end
  )
end

# A docs.json holding nothing but the named types, which is all the index reads.
private def document_json(type_names : Array(String)) : String
  types = type_names.map do |full_name|
    short = full_name.split("::").last
    %({"full_name": #{full_name.inspect}, "name": #{short.inspect}, "kind": "class"})
  end

  %({"program": {"full_name": "Top Level Namespace", "name": "Top Level Namespace", "types": [#{types.join(",")}]}})
end

private def document_package(package_name : String, versions : Array(String))
  doc = DocFactory.create &.package_name(package_name).current_version(versions.last)

  versions.each do |version|
    DocVersionFactory.create &.doc_id(doc.id)
      .version(version)
      .storage_path("#{package_name}/#{version}")
  end
end

private def with_registry(
  registry : CrystalDocs::RegistryMetadata,
  documents : Hash(String, String),
  &
)
  CrystalDocs::RegistryMetadata.provider = -> { registry.as(CrystalDocs::RegistryMetadata) }
  CrystalDocs::DocsLoader.loader = -> { FakeLoader.new(documents).as(CrystalDocs::DocsLoader) }
  CrystalDocs::DependencyIndex.clear_cache

  yield
ensure
  CrystalDocs::RegistryMetadata.provider = nil
  CrystalDocs::DocsLoader.loader = nil
  CrystalDocs::DependencyIndex.clear_cache
end

describe CrystalDocs::DependencyIndex do
  describe "honouring the source version's own requirement" do
    it "links the version that was pinned, not the newest documented one" do
      document_package("crystal", ["1.9.0"])
      document_package("kemal", ["1.2.0", "1.3.0"])

      registry = FakeRegistry.new(
        declares(">= 1.0.0", {"kemal" => "~> 1.2.0"}),
        {"kemal" => [published("1.2.0", ">= 1.0.0"), published("1.3.0", ">= 1.0.0")]}
      )

      documents = {
        "crystal/1.9.0" => document_json(["String"]),
        "kemal/1.2.0"   => document_json(["Kemal::Handler"]),
        "kemal/1.3.0"   => document_json(["Kemal::Handler", "Kemal::WebSocket"]),
      }

      with_registry(registry, documents) do
        index = CrystalDocs::DependencyIndex.for("consumer", "1.0.0")

        index["Kemal::Handler"]?.should eq({package: "kemal", version: "1.2.0"})
        # The whole point. Kemal::WebSocket arrives in 1.3.0, which this
        # reader's release excluded, so the name has no link at all rather
        # than one pointing at API that did not exist for them.
        index["Kemal::WebSocket"]?.should be_nil
      end
    end

    it "leaves the name plain when no documented version satisfies" do
      document_package("crystal", ["1.9.0"])
      document_package("kemal", ["2.0.0"])

      registry = FakeRegistry.new(
        declares(">= 1.0.0", {"kemal" => "~> 1.2.0"}),
        {"kemal" => [published("2.0.0", ">= 1.0.0")]}
      )

      documents = {
        "crystal/1.9.0" => document_json(["String"]),
        "kemal/2.0.0"   => document_json(["Kemal::Handler"]),
      }

      with_registry(registry, documents) do
        index = CrystalDocs::DependencyIndex.for("consumer", "1.0.0")

        # Never the newest as a consolation prize.
        index["Kemal::Handler"]?.should be_nil
        index["String"]?.should eq({package: "crystal", version: "1.9.0"})
      end
    end
  end

  describe "honouring the Crystal version" do
    it "selects the standard library the source declared support for" do
      document_package("crystal", ["1.8.0", "1.9.0", "1.10.0"])

      registry = FakeRegistry.new(
        declares("~> 1.9.0", {} of String => String),
        {} of String => Array(CrystalDocs::RegistryMetadata::PublishedVersion)
      )

      documents = {
        "crystal/1.8.0"  => document_json(["String"]),
        "crystal/1.9.0"  => document_json(["String"]),
        "crystal/1.10.0" => document_json(["String", "Log::Emitter"]),
      }

      with_registry(registry, documents) do
        index = CrystalDocs::DependencyIndex.for("consumer", "1.0.0")

        # 1.10.0 is the highest, and is numerically higher than 1.9.0 rather
        # than lexically lower, but "~> 1.9.0" stops at 1.10.0.
        index["String"]?.should eq({package: "crystal", version: "1.9.0"})
        index["Log::Emitter"]?.should be_nil
      end
    end

    it "skips a dependency release that needs a newer Crystal" do
      document_package("crystal", ["1.9.0"])
      document_package("kemal", ["1.2.0", "1.3.0"])

      registry = FakeRegistry.new(
        # The requirement alone would allow 1.3.0.
        declares(">= 1.0.0", {"kemal" => "~> 1.2"}),
        {"kemal" => [
          published("1.2.0", ">= 1.0.0"),
          published("1.3.0", ">= 1.20.0"),
        ]}
      )

      documents = {
        "crystal/1.9.0" => document_json(["String"]),
        "kemal/1.2.0"   => document_json(["Kemal::Handler"]),
        "kemal/1.3.0"   => document_json(["Kemal::Handler", "Kemal::WebSocket"]),
      }

      with_registry(registry, documents) do
        index = CrystalDocs::DependencyIndex.for("consumer", "1.0.0")

        index["Kemal::Handler"]?.should eq({package: "kemal", version: "1.2.0"})
        index["Kemal::WebSocket"]?.should be_nil
      end
    end

    it "skips a dependency release that declared no Crystal support" do
      document_package("crystal", ["1.9.0"])
      document_package("kemal", ["1.2.0"])

      registry = FakeRegistry.new(
        declares(">= 1.0.0", {"kemal" => "~> 1.2"}),
        {"kemal" => [published("1.2.0", nil)]}
      )

      documents = {
        "crystal/1.9.0" => document_json(["String"]),
        "kemal/1.2.0"   => document_json(["Kemal::Handler"]),
      }

      with_registry(registry, documents) do
        index = CrystalDocs::DependencyIndex.for("consumer", "1.0.0")

        # Absent metadata is not permission.
        index["Kemal::Handler"]?.should be_nil
      end
    end
  end

  describe "missing metadata" do
    it "links nothing when the source declared no Crystal version" do
      document_package("crystal", ["1.9.0"])
      document_package("kemal", ["1.2.0"])

      registry = FakeRegistry.new(
        declares(nil, {"kemal" => "~> 1.2"}),
        {"kemal" => [published("1.2.0", ">= 1.0.0")]}
      )

      documents = {
        "crystal/1.9.0" => document_json(["String"]),
        "kemal/1.2.0"   => document_json(["Kemal::Handler"]),
      }

      with_registry(registry, documents) do
        CrystalDocs::DependencyIndex.for("consumer", "1.0.0").should be_empty
      end
    end

    it "links nothing when the registry has never seen the version" do
      document_package("crystal", ["1.9.0"])

      registry = FakeRegistry.new(
        nil,
        {} of String => Array(CrystalDocs::RegistryMetadata::PublishedVersion)
      )

      with_registry(registry, {"crystal/1.9.0" => document_json(["String"])}) do
        CrystalDocs::DependencyIndex.for("consumer", "1.0.0").should be_empty
      end
    end
  end

  describe "collisions" do
    it "leaves a name plain when two dependencies define it" do
      document_package("crystal", ["1.9.0"])
      document_package("kemal", ["1.2.0"])
      document_package("granite", ["1.0.0"])

      registry = FakeRegistry.new(
        declares(">= 1.0.0", {"kemal" => "~> 1.2", "granite" => "~> 1.0"}),
        {
          "kemal"   => [published("1.2.0", ">= 1.0.0")],
          "granite" => [published("1.0.0", ">= 1.0.0")],
        }
      )

      documents = {
        "crystal/1.9.0" => document_json(["String"]),
        "kemal/1.2.0"   => document_json(["Config", "Kemal::Handler"]),
        "granite/1.0.0" => document_json(["Config", "Granite::Base"]),
      }

      with_registry(registry, documents) do
        index = CrystalDocs::DependencyIndex.for("consumer", "1.0.0")

        index["Config"]?.should be_nil
        index["Kemal::Handler"]?.should eq({package: "kemal", version: "1.2.0"})
        index["Granite::Base"]?.should eq({package: "granite", version: "1.0.0"})
      end
    end

    it "gives a standard library name to the standard library" do
      document_package("crystal", ["1.9.0"])
      document_package("kemal", ["1.2.0"])

      registry = FakeRegistry.new(
        declares(">= 1.0.0", {"kemal" => "~> 1.2"}),
        {"kemal" => [published("1.2.0", ">= 1.0.0")]}
      )

      documents = {
        "crystal/1.9.0" => document_json(["String"]),
        # Shards reopen standard library types routinely.
        "kemal/1.2.0" => document_json(["String", "Kemal::Handler"]),
      }

      with_registry(registry, documents) do
        index = CrystalDocs::DependencyIndex.for("consumer", "1.0.0")

        index["String"]?.should eq({package: "crystal", version: "1.9.0"})
      end
    end

    it "never links a package to itself" do
      document_package("crystal", ["1.9.0"])
      document_package("kemal", ["1.2.0"])

      registry = FakeRegistry.new(
        declares(">= 1.0.0", {"kemal" => "~> 1.2"}),
        {"kemal" => [published("1.2.0", ">= 1.0.0")]}
      )

      documents = {
        "crystal/1.9.0" => document_json(["String"]),
        "kemal/1.2.0"   => document_json(["Kemal::Handler"]),
      }

      with_registry(registry, documents) do
        index = CrystalDocs::DependencyIndex.for("kemal", "1.2.0")

        # Local names resolve locally, with current page highlighting.
        index["Kemal::Handler"]?.should be_nil
        index["String"]?.should eq({package: "crystal", version: "1.9.0"})
      end
    end
  end
end
