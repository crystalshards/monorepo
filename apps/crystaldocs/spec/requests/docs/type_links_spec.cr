require "../../spec_helper"

# A document per package version, because the point of these examples is that
# one page names types defined in three different ones.
private class KeyedDocsStorage < CrystalDocs::DocsStorageService
  def initialize(@documents : Hash(String, String))
    super()
  end

  def fetch_doc_file(package_name : String, version : String, file_path : String) : CrystalDocs::DocsStorageService::Fetch
    raw = @documents["#{package_name}/#{version}"]?
    return CrystalDocs::DocsStorageService::Fetch.absent unless raw

    CrystalDocs::DocsStorageService::Fetch.found(raw)
  end

  def install : KeyedDocsStorage
    storage = self
    CrystalDocs::DocsLoader.clear_cache
    CrystalDocs::DocsLoader.loader = -> { CrystalDocs::DocsLoader.new(storage) }
    self
  end
end

# A type whose one instance method takes a standard library type and returns a
# dependency's, which is the shape of nearly every signature a reader meets.
private def handler_document : String
  <<-JSON
    {
      "program": {
        "full_name": "Top Level Namespace",
        "name": "Top Level Namespace",
        "types": [
          {
            "full_name": "Kemal::Handler",
            "name": "Handler",
            "kind": "class",
            "ancestors": [{"full_name": "HTTP::Handler"}],
            "instance_methods": [
              {
                "name": "call",
                "args_string": "(context : HTTP::Server::Context, tree : Radix::Tree)",
                "return_type": "Kemal::Config"
              }
            ]
          },
          {"full_name": "Kemal::Config", "name": "Config", "kind": "class"}
        ]
      }
    }
    JSON
end

private def types_document(full_names : Array(String)) : String
  types = full_names.map do |full_name|
    short = full_name.split("::").last
    %({"full_name": #{full_name.inspect}, "name": #{short.inspect}, "kind": "class"})
  end

  %({"program": {"full_name": "Top Level Namespace", "name": "Top Level Namespace", "types": [#{types.join(",")}]}})
end

private def document_package(package_name : String, versions : Array(String))
  return if versions.empty?

  doc = DocFactory.create &.package_name(package_name).current_version(versions.last)

  versions.each do |version|
    DocVersionFactory.create &.doc_id(doc.id)
      .version(version)
      .storage_path("#{package_name}/#{version}")
  end
end

# The page Jason was looking at, minus the parts that do not decide a link.
#
# Every name on it rendered as plain text: `HTTP::Handler` from the standard
# library, `Radix::Tree` from a declared dependency, and only the package's own
# `Kemal::Config` linked. These assert on the rendered anchors rather than on
# the index, because the index being right is not the same claim as the reader
# being able to click.
describe "type names on a rendered documentation page" do
  get = ->(path : String) { BrowserClient.exec(Lucky::RouteHelper.new(:get, path)) }

  kemal = "github.com/kemalcr/kemal"
  radix = "github.com/luislavena/radix"
  page = "/docs/_/github.com/kemalcr/kemal/1.12.0/Kemal/Handler"

  seed = ->(crystal_versions : Array(String)) do
    RegistrySchema.reset
    kemal_shard = RegistrySchema.shard("kemal", kemal)
    radix_shard = RegistrySchema.shard("radix", radix)
    release = RegistrySchema.version(kemal_shard, "1.12.0", "~> 1.12.0")
    RegistrySchema.version(radix_shard, "0.4.0", ">= 1.0.0")
    RegistrySchema.dependency(release, "radix", "~> 0.4.0", resolved_shard_id: radix_shard)

    document_package(kemal, ["1.12.0"])
    document_package(radix, ["0.4.0"])
    document_package("crystal", crystal_versions)

    documents = {
      "#{kemal}/1.12.0" => handler_document,
      "#{radix}/0.4.0"  => types_document(["Radix::Tree"]),
    }

    crystal_versions.each do |version|
      documents["crystal/#{version}"] =
        types_document(["HTTP::Handler", "HTTP::Server::Context", "String"])
    end

    KeyedDocsStorage.new(documents).install
    CrystalDocs::DependencyIndex.clear_cache
  end

  after_each { CrystalDocs::DependencyIndex.clear_cache }

  it "links a standard library name to the standard library" do
    seed.call(["1.12.0"])

    body = get.call(page).body

    body.should contain(%(href="/docs/crystal/1.12.0/HTTP/Handler"))
    body.should contain(%(href="/docs/crystal/1.12.0/HTTP/Server/Context"))
  end

  it "links a dependency name to that dependency at the resolved version" do
    seed.call(["1.12.0"])

    get.call(page).body
      .should contain(%(href="/docs/_/github.com/luislavena/radix/0.4.0/Radix/Tree"))
  end

  it "still links the package's own types to itself" do
    seed.call(["1.12.0"])

    get.call(page).body
      .should contain(%(href="/docs/_/github.com/kemalcr/kemal/1.12.0/Kemal/Config"))
  end

  # The standard library build for the era this shard targets, never the
  # newest one on the site.
  it "links the standard library the shard declared support for" do
    seed.call(["1.12.0", "1.14.0"])

    body = get.call(page).body

    body.should contain(%(href="/docs/crystal/1.12.0/HTTP/Handler"))
    body.should_not contain("/docs/crystal/1.14.0/")
  end

  it "names the package a cross link leaves for" do
    seed.call(["1.12.0"])

    body = get.call(page).body

    body.should contain(%(title="HTTP::Handler in the Crystal standard library 1.12.0"))
    body.should contain(%(title="Radix::Tree in github.com/luislavena/radix 0.4.0"))
  end

  # Nothing built for that Crystal, so the page it would point at does not
  # exist. Plain text is the answer; a 404 dressed as a link is not.
  it "leaves a standard library name plain when that Crystal is not built" do
    seed.call([] of String)

    body = get.call(page).body

    body.should contain("HTTP::Handler")
    body.should_not contain("/docs/crystal/")
    # And the dependency is unaffected by the standard library being absent.
    body.should contain(%(href="/docs/_/github.com/luislavena/radix/0.4.0/Radix/Tree"))
  end
end
