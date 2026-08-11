# A documentation store with a scripted answer.
#
# The three outcomes the version action distinguishes (a document, storage
# answering with nothing, storage not answering at all) are properties of the
# store, so they are set here rather than by planting and deleting objects in
# a real bucket. That also keeps examples about the build queue from depending
# on MinIO being up.
class StubDocsStorage < CrystalDocs::DocsStorageService
  MINIMAL_DOCUMENT = {
    repository_name: "stub",
    body:            "# Stub\n\nA planted document.",
    program:         {
      full_name: "Top Level Namespace",
      name:      "Top Level Namespace",
      kind:      "module",
      types:     [] of String,
    },
  }.to_json

  def initialize(@fetch : CrystalDocs::DocsStorageService::Fetch)
    super()
  end

  def self.holding(raw : String = MINIMAL_DOCUMENT) : StubDocsStorage
    new(CrystalDocs::DocsStorageService::Fetch.found(raw))
  end

  # The store answered, and this version has never been built.
  def self.empty : StubDocsStorage
    new(CrystalDocs::DocsStorageService::Fetch.absent)
  end

  # The store could not be reached, so whether it exists is unknown.
  def self.unreachable : StubDocsStorage
    new(CrystalDocs::DocsStorageService::Fetch.unavailable)
  end

  def fetch_doc_file(package_name : String, version : String, file_path : String) : CrystalDocs::DocsStorageService::Fetch
    @fetch
  end

  # Installs this store behind DocsLoader for one example. The loader's own
  # cache is cleared first: it is keyed on package and version, and examples
  # reuse both.
  def install : StubDocsStorage
    storage = self
    CrystalDocs::DocsLoader.clear_cache
    CrystalDocs::DocsLoader.loader = -> { CrystalDocs::DocsLoader.new(storage) }
    self
  end
end

Spec.after_each do
  CrystalDocs::DocsLoader.loader = nil
  CrystalDocs::DocsLoader.clear_cache
end
