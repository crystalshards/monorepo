require "../spec_helper"

# The switcher's source of truth.
#
# Runs against the real registry schema for the same reason
# `registry_metadata_spec` does: the join between `docs.package_name` and
# `shards.canonical_slug` is the part that has been wrong before, and a fake
# registry cannot see it.
private def catalogue_for(package_name : String) : Array(CrystalDocs::VersionCatalogue::Entry)
  doc = DocQuery.new.preload_doc_versions.package_name(package_name).first
  CrystalDocs::VersionCatalogue.for(doc)
end

describe CrystalDocs::VersionCatalogue do
  it "lists versions the registry published that this site has never built" do
    RegistrySchema.reset
    kemal = RegistrySchema.shard("kemal", "github.com/kemalcr/kemal")
    RegistrySchema.version(kemal, "1.12.0")
    RegistrySchema.version(kemal, "1.11.0")
    RegistrySchema.version(kemal, "1.10.0")

    doc = DocFactory.create &.package_name("github.com/kemalcr/kemal")
    DocVersionFactory.create &.doc_id(doc.id).version("1.12.0").build_status("success")

    entries = catalogue_for("github.com/kemalcr/kemal")

    # The whole point: two of these have no doc_versions row at all, and
    # before this they were unreachable except by typing the URL.
    entries.map(&.version).should eq(["1.12.0", "1.11.0", "1.10.0"])
    entries.map(&.state).should eq([
      CrystalDocs::VersionCatalogue::State::Built,
      CrystalDocs::VersionCatalogue::State::Unbuilt,
      CrystalDocs::VersionCatalogue::State::Unbuilt,
    ])
  end

  it "orders by version precedence rather than by string" do
    # The regression this exists to stop. Lexically "1.10.0" sorts below
    # "1.9.0", so the old switcher offered 1.9.0 as the newest release of any
    # package that had reached a double digit minor.
    RegistrySchema.reset
    shard = RegistrySchema.shard("widget", "github.com/acme/widget")
    ["1.9.0", "1.10.0", "1.2.0", "2.0.0"].each { |v| RegistrySchema.version(shard, v) }

    DocFactory.create &.package_name("github.com/acme/widget")

    catalogue_for("github.com/acme/widget").map(&.version)
      .should eq(["2.0.0", "1.10.0", "1.9.0", "1.2.0"])
  end

  it "keeps this site's build state for a version the registry also knows" do
    # The registry knows a version was published. It does not know whether we
    # rendered it, so it must never overwrite a local row.
    RegistrySchema.reset
    shard = RegistrySchema.shard("widget", "github.com/acme/widget")
    RegistrySchema.version(shard, "1.0.0")
    RegistrySchema.version(shard, "0.9.0")

    doc = DocFactory.create &.package_name("github.com/acme/widget")
    DocVersionFactory.create &.doc_id(doc.id).version("1.0.0").build_status("failed")
    DocVersionFactory.create &.doc_id(doc.id).version("0.9.0").build_status("pending")

    catalogue_for("github.com/acme/widget").map(&.state).should eq([
      CrystalDocs::VersionCatalogue::State::Failed,
      CrystalDocs::VersionCatalogue::State::Building,
    ])
  end

  it "keeps a version this site holds that the registry has dropped" do
    # A yanked release still has documentation we built and a reader may still
    # be on that page. Dropping it from the switcher would strand them.
    RegistrySchema.reset
    shard = RegistrySchema.shard("widget", "github.com/acme/widget")
    RegistrySchema.version(shard, "1.1.0")
    RegistrySchema.version(shard, "1.0.0", yanked: true)

    doc = DocFactory.create &.package_name("github.com/acme/widget")
    DocVersionFactory.create &.doc_id(doc.id).version("1.0.0").build_status("success")

    entries = catalogue_for("github.com/acme/widget")

    entries.map(&.version).should eq(["1.1.0", "1.0.0"])
    entries.map(&.state).should eq([
      CrystalDocs::VersionCatalogue::State::Unbuilt,
      CrystalDocs::VersionCatalogue::State::Built,
    ])
  end

  it "sorts a tag that is not a version below every one that is" do
    # Kept rather than dropped: it is a row we hold, and a reader looking for
    # it should find it at the bottom instead of concluding it is gone.
    RegistrySchema.reset
    shard = RegistrySchema.shard("widget", "github.com/acme/widget")
    RegistrySchema.version(shard, "nightly")
    RegistrySchema.version(shard, "1.0.0")

    DocFactory.create &.package_name("github.com/acme/widget")

    catalogue_for("github.com/acme/widget").map(&.version)
      .should eq(["1.0.0", "nightly"])
  end

  it "answers with what this site holds when the registry knows nothing" do
    RegistrySchema.reset

    doc = DocFactory.create &.package_name("github.com/acme/orphan")
    DocVersionFactory.create &.doc_id(doc.id).version("1.0.0").build_status("success")

    entries = catalogue_for("github.com/acme/orphan")

    entries.map(&.version).should eq(["1.0.0"])
    entries.first.built?.should be_true
  end
end
