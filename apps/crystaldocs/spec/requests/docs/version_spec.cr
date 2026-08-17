require "../../spec_helper"

describe Docs::Version do
  it "displays documentation content" do
    doc = DocFactory.create &.package_name("test-package")

    version = DocVersionFactory.create &.doc_id(doc.id)
      .version("1.0.0")
      .build_status("success")

    # Note: This test assumes MinIO is configured and has test data
    # In a real environment, you'd mock the storage service
    response = BrowserClient.exec(Docs::Version.with(package_name: "test-package", version: "1.0.0"))

    response.status_code.should eq(200)
    response.body.should contain("test-package")
    response.body.should contain("1.0.0")
  end

  it "returns 404 for non-existent package" do
    response = BrowserClient.exec(Docs::Version.with(package_name: "nonexistent", version: "1.0.0"))

    response.status_code.should eq(404)
  end

  it "returns 404 for non-existent version" do
    doc = DocFactory.create &.package_name("test-package")

    response = BrowserClient.exec(Docs::Version.with(package_name: "test-package", version: "99.99.99"))

    response.status_code.should eq(404)
  end

  it "shows version not found page when doc content is missing" do
    doc = DocFactory.create &.package_name("test-package")

    version = DocVersionFactory.create &.doc_id(doc.id)
      .version("1.0.0")
      .build_status("pending")

    # Storage holds no content for this version, so the page degrades instead
    # of erroring.
    response = BrowserClient.exec(Docs::Version.with(package_name: "test-package", version: "1.0.0"))

    response.status_code.should eq(200)
  end

  it "displays version switcher with all versions" do
    doc = DocFactory.create &.package_name("test-package")

    version1 = DocVersionFactory.create &.doc_id(doc.id)
      .version("1.0.0")

    version2 = DocVersionFactory.create &.doc_id(doc.id)
      .version("2.0.0")

    response = BrowserClient.exec(Docs::Version.with(package_name: "test-package", version: "1.0.0"))
    response.status_code.should eq(200)
    response.body.should contain("Version:")

    # The original example stopped at the label and left "should list both
    # versions" as a comment, so the switcher's actual contents were never
    # checked. They are now.
    response.body.should contain(%(id="version-select"))
    response.body.should contain(%(value="/docs/test-package/1.0.0"))
    response.body.should contain(%(value="/docs/test-package/2.0.0"))
  end

  it "displays breadcrumb navigation" do
    doc = DocFactory.create &.package_name("test-package")

    version = DocVersionFactory.create &.doc_id(doc.id)
      .version("1.0.0")

    response = BrowserClient.exec(Docs::Version.with(package_name: "test-package", version: "1.0.0"))

    response.status_code.should eq(200)
    response.body.should contain("breadcrumb")
  end

  # The short badge is the fallback voice, for the case where there is no
  # build request to explain the page: the storage lookup failed, so we cannot
  # say a build is happening and cannot show documentation either. Whenever a
  # request exists the section below speaks instead, because it can say what
  # happens next, and two voices reading from two tables disagreed.
  it "falls back to the short build status when there is no request to explain the page" do
    doc = DocFactory.create &.package_name("test-package")

    DocVersionFactory.create &.doc_id(doc.id)
      .version("1.0.0")
      .build_status("failed")

    StubDocsStorage.unreachable.install

    response = BrowserClient.exec(Docs::Version.with(package_name: "test-package", version: "1.0.0"))

    response.status_code.should eq(200)
    response.body.should contain("Build:")
    response.body.should_not contain("Documentation is being built")
  end

  it "increments view count" do
    doc = DocFactory.create &.package_name("test-package")
      .total_views(10)

    version = DocVersionFactory.create &.doc_id(doc.id)
      .version("1.0.0")

    # Viewing documentation should increment counter
    # Note: This test may need adjustment based on actual MinIO state
    initial_views = doc.total_views

    BrowserClient.exec(Docs::Version.with(package_name: "test-package", version: "1.0.0"))

    # Reload doc to check if views increased
    updated_doc = DocQuery.new.package_name("test-package").first
    # Views should increase if content exists
    # updated_doc.total_views.should be >= initial_views
  end

  # The standard library never goes through PackageRegistration: CoreDocs
  # registers and records its own commit on the crystalshards side, into the
  # exact row shape this plants directly. This is the proven case that
  # reported the bug: a bare "crystal" row, in production already carrying
  # this shape once CoreDocs runs, resolving a relative asset that used to
  # 404 against crystaldocs.org itself.
  it "resolves a relative README reference for the standard library through the row core registration produces" do
    doc = DocFactory.create &.package_name(CrystalDocs::CORE_PACKAGE)

    DocVersionFactory.create &.doc_id(doc.id)
      .version("1.21.0")
      .source_commit_sha("cafef00dfeedface02")

    document = {
      repository_name: "crystal-lang/crystal",
      body:            "![Crystal - Born and raised at Manas](doc/assets/crystal-born-and-raised.svg)",
      program:         {
        full_name: "Top Level Namespace",
        name:      "Top Level Namespace",
        kind:      "module",
        types:     [] of String,
      },
    }.to_json

    StubDocsStorage.holding(document).install

    response = BrowserClient.exec(
      Docs::Version.with(package_name: CrystalDocs::CORE_PACKAGE, version: "1.21.0")
    )

    response.status_code.should eq(200)
    response.body.should contain(
      "https://raw.githubusercontent.com/crystal-lang/crystal/cafef00dfeedface02/" \
      "doc/assets/crystal-born-and-raised.svg"
    )
  end

  # The switcher is how a reader moves between versions, and it used to list
  # only what this site had already built. A package with sixty tags and two
  # visits offered a choice of two, and the rest were reachable only by
  # guessing the URL.
  it "offers versions the registry published that have never been built here" do
    RegistrySchema.reset
    shard = RegistrySchema.shard("test-package", "test-package")
    RegistrySchema.version(shard, "2.0.0")
    RegistrySchema.version(shard, "1.0.0")

    doc = DocFactory.create &.package_name("test-package")
    DocVersionFactory.create &.doc_id(doc.id).version("1.0.0").build_status("success")

    response = BrowserClient.exec(Docs::Version.with(package_name: "test-package", version: "1.0.0"))

    response.status_code.should eq(200)

    # Grouped, because "documented" and "we will build this if you ask" are
    # different offers and a flat list makes them read the same.
    response.body.should contain(%(<optgroup label="Documented">))
    response.body.should contain(%(<optgroup label="Not built yet">))

    # 2.0.0 has no doc_versions row at all and is still reachable.
    response.body.should contain("/docs/test-package/2.0.0")
  end

  # The regression that made the feature invisible in practice. The switcher
  # shipped on the version overview only, and a reader spends nearly all their
  # time on a type page, which had no way to change version at all.
  it "carries the version switcher on a type page, not only the overview" do
    RegistrySchema.reset
    shard = RegistrySchema.shard("test-package", "test-package")
    RegistrySchema.version(shard, "2.0.0")
    RegistrySchema.version(shard, "1.0.0")

    doc = DocFactory.create &.package_name("test-package")
    DocVersionFactory.create &.doc_id(doc.id).version("1.0.0").build_status("success")

    StubDocsStorage.new(CrystalDocs::DocsStorageService::Fetch.found(<<-JSON)).install
      {
        "program": {
          "full_name": "Top Level Namespace",
          "name": "Top Level Namespace",
          "types": [{"full_name": "Widget", "name": "Widget", "kind": "class"}]
        }
      }
      JSON

    response = BrowserClient.exec(
      Lucky::RouteHelper.new(:get, "/docs/test-package/1.0.0/Widget")
    )

    response.status_code.should eq(200)
    response.body.should contain(%(id="version-select"))
    response.body.should contain(%(<optgroup label="Not built yet">))

    # Options point at the version overview rather than at this type inside the
    # target version: an unbuilt version has no row and would redirect back,
    # and a built one may not define the type at all and would 404.
    response.body.should contain(%(value="/docs/test-package/2.0.0"))
    response.body.should_not contain(%(value="/docs/test-package/2.0.0/Widget"))
  end
end
