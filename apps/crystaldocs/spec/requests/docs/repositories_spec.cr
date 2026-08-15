require "../../spec_helper"

# Documentation addressed by repository.
#
# The whole point of these URLs is that they answer for a shard nobody has ever
# documented. Before them, the version route looked for a row, found none for
# 217 of the registry's shards, and raised route-not-found before the lazy
# build it already had could fire.
describe "documentation for a repository" do
  get = ->(path : String) { BrowserClient.exec(Lucky::RouteHelper.new(:get, path)) }

  kemal = "/docs/_/github.com/kemalcr/kemal"

  describe "a package the registry has and this app has never seen" do
    it "registers it and asks for a build instead of 404ing" do
      StubRegistryPackages.new.publish("github.com/kemalcr/kemal", "kemal", ["1.6.0"]).install
      StubDocsStorage.empty.install
      RecordingBuildQueue.install

      response = get.call("#{kemal}/1.6.0")

      response.status_code.should eq(200)
      response.body.should contain("Documentation is being built")
    end

    it "creates the rows the build pipeline needs, keyed on the repository" do
      StubRegistryPackages.new.publish("github.com/kemalcr/kemal", "kemal", ["1.6.0"]).install
      StubDocsStorage.empty.install

      get.call("#{kemal}/1.6.0")

      doc = DocQuery.new.preload_doc_versions.package_name("github.com/kemalcr/kemal").first
      doc.doc_versions.map(&.version).should eq(["1.6.0"])
      doc.doc_versions.first.build_status.should eq("pending")
    end

    it "stores the artifact under the repository, not under the shard name" do
      StubRegistryPackages.new.publish("github.com/kemalcr/kemal", "kemal", ["1.6.0"]).install
      StubDocsStorage.empty.install

      get.call("#{kemal}/1.6.0")

      DocVersionQuery.new.version("1.6.0").first.storage_path
        .should eq("github.com/kemalcr/kemal/1.6.0")
    end

    it "commissions exactly one build however many readers arrive" do
      StubRegistryPackages.new.publish("github.com/kemalcr/kemal", "kemal", ["1.6.0"]).install
      StubDocsStorage.empty.install
      queue = RecordingBuildQueue.install

      5.times { get.call("#{kemal}/1.6.0") }

      queue.enqueued.size.should eq(1)
      queue.count_for("github.com/kemalcr/kemal", "1.6.0").should eq(1)
    end

    it "creates one row however many readers arrive" do
      StubRegistryPackages.new.publish("github.com/kemalcr/kemal", "kemal", ["1.6.0"]).install
      StubDocsStorage.empty.install

      5.times { get.call("#{kemal}/1.6.0") }

      DocQuery.new.package_name("github.com/kemalcr/kemal").select_count.should eq(1)
      DocVersionQuery.new.version("1.6.0").select_count.should eq(1)
    end

    it "records the registry's current release rather than the one requested" do
      StubRegistryPackages.new
        .publish("github.com/kemalcr/kemal", "kemal", ["1.0.0", "1.6.0"])
        .install
      StubDocsStorage.empty.install

      get.call("#{kemal}/1.0.0")

      DocQuery.new.package_name("github.com/kemalcr/kemal").first.current_version
        .should eq("1.6.0")
    end
  end

  describe "a package the registry does not have" do
    it "404s rather than registering anything" do
      StubRegistryPackages.install
      StubDocsStorage.empty.install

      response = get.call("/docs/_/github.com/nobody/invented/1.0.0")

      response.status_code.should eq(404)
      DocQuery.new.select_count.should eq(0)
    end

    it "404s even when a row exists under that key" do
      doc = DocFactory.create &.package_name("github.com/nobody/invented").current_version("1.0.0")
      DocVersionFactory.create &.doc_id(doc.id).version("1.0.0")
      StubRegistryPackages.install
      StubDocsStorage.holding.install

      get.call("/docs/_/github.com/nobody/invented/1.0.0").status_code.should eq(404)
    end

    it "commissions no build" do
      StubRegistryPackages.install
      StubDocsStorage.empty.install
      queue = RecordingBuildQueue.install

      get.call("/docs/_/github.com/nobody/invented/1.0.0")

      queue.enqueued.should be_empty
    end

    # A crawler walking versions of a real shard must not create a row per
    # invented version, or the URL bar becomes the build queue.
    it "404s a version the registry never published" do
      StubRegistryPackages.new.publish("github.com/kemalcr/kemal", "kemal", ["1.6.0"]).install
      StubDocsStorage.empty.install
      queue = RecordingBuildQueue.install

      get.call("#{kemal}/9.9.9").status_code.should eq(404)

      queue.enqueued.should be_empty
      DocVersionQuery.new.version("9.9.9").select_count.should eq(0)
    end
  end

  describe "two repositories publishing the same shard name" do
    tunkshif = "github.com/TunkShif/lsp.cr"
    elbywan = "github.com/elbywan/crystal-lsp"

    collision = -> {
      StubRegistryPackages.new
        .publish(tunkshif, "lsp", ["0.1.0"])
        .publish(elbywan, "lsp", ["2.0.0"])
        .install
    }

    it "documents each repository under its own key" do
      collision.call
      StubDocsStorage.empty.install

      get.call("/docs/_/#{tunkshif}/0.1.0")
      get.call("/docs/_/#{elbywan}/2.0.0")

      DocQuery.new.preload_doc_versions.package_name(tunkshif).first
        .doc_versions.map(&.version).should eq(["0.1.0"])
      DocQuery.new.preload_doc_versions.package_name(elbywan).first
        .doc_versions.map(&.version).should eq(["2.0.0"])
    end

    it "commissions a separate build per repository" do
      collision.call
      StubDocsStorage.empty.install
      queue = RecordingBuildQueue.install

      get.call("/docs/_/#{tunkshif}/0.1.0")
      get.call("/docs/_/#{elbywan}/2.0.0")

      queue.count_for(tunkshif, "0.1.0").should eq(1)
      queue.count_for(elbywan, "2.0.0").should eq(1)
    end

    it "keeps their artifacts apart" do
      collision.call
      StubDocsStorage.empty.install

      get.call("/docs/_/#{tunkshif}/0.1.0")
      get.call("/docs/_/#{elbywan}/2.0.0")

      DocVersionQuery.new.preload_doc.results.map(&.storage_path).sort!.should eq([
        "github.com/TunkShif/lsp.cr/0.1.0",
        "github.com/elbywan/crystal-lsp/2.0.0",
      ])
    end

    # The version each repository publishes is not the version the other
    # publishes, so asking one for the other's release is a 404 and never a
    # quiet substitution.
    it "refuses one repository's version under the other's URL" do
      collision.call
      StubDocsStorage.empty.install

      get.call("/docs/_/#{tunkshif}/2.0.0").status_code.should eq(404)
    end

    it "hands the choice back at the bare name rather than picking one" do
      collision.call

      response = get.call("/docs/lsp")

      response.status_code.should eq(200)
      response.body.should contain(tunkshif)
      response.body.should contain(elbywan)
    end

    # The bare name is the URL that is already indexed, and a row under it
    # cannot be attributed to a repository. Serving it would be exactly the
    # failure host qualified identity exists to remove.
    it "does not serve a row held under the ambiguous name" do
      doc = DocFactory.create &.package_name("lsp").current_version("0.0.1")
      DocVersionFactory.create &.doc_id(doc.id).version("0.0.1")
      collision.call
      StubDocsStorage.holding.install

      response = get.call("/docs/lsp/0.0.1")

      response.body.should_not contain("Version:")
      response.body.should contain(tunkshif)
    end
  end

  describe "a repository with no release" do
    it "says so rather than erroring" do
      StubRegistryPackages.new.publish("github.com/lbguilherme/lsp", "lsp").install

      response = get.call("/docs/_/github.com/lbguilherme/lsp")

      response.status_code.should eq(200)
      response.body.should contain("no published releases")
    end

    # The bug Jason caught on crystaldocs.org. kemal has 65 tags and the page
    # said it had no published releases, because the registry had discovered
    # the repository and had not yet read it. An empty release list before
    # indexing is a gap in our database, and we do not get to report it as a
    # fact about somebody's repository.
    it "does not claim a repository has no releases before the registry read it" do
      StubRegistryPackages.new
        .publish("github.com/kemalcr/kemal", "kemal", indexed: false)
        .install

      response = get.call("/docs/_/github.com/kemalcr/kemal")

      response.status_code.should eq(200)
      response.body.should contain("not been read yet")
      response.body.should_not contain("no published releases")
    end

    it "commissions nothing, because there is nothing to build" do
      StubRegistryPackages.new.publish("github.com/lbguilherme/lsp", "lsp").install
      queue = RecordingBuildQueue.install

      get.call("/docs/_/github.com/lbguilherme/lsp")

      queue.enqueued.should be_empty
      DocQuery.new.select_count.should eq(0)
    end

    it "distinguishes a repository whose releases were all withdrawn" do
      StubRegistryPackages.new
        .publish("github.com/acme/gone", "gone", ["1.0.0"], yanked: ["1.0.0"])
        .install

      response = get.call("/docs/_/github.com/acme/gone")

      response.status_code.should eq(200)
      response.body.should contain("withdrawn")
    end

    # A withdrawn release is never the default, and is still reachable by name.
    it "still documents a withdrawn release that is asked for directly" do
      StubRegistryPackages.new
        .publish("github.com/acme/gone", "gone", ["1.0.0"], yanked: ["1.0.0"])
        .install
      StubDocsStorage.empty.install

      response = get.call("/docs/_/github.com/acme/gone/1.0.0")

      response.status_code.should eq(200)
      DocVersionQuery.new.version("1.0.0").select_count.should eq(1)
    end
  end

  describe "a repository without a version in the URL" do
    it "goes to the current release, by precedence and not by string order" do
      StubRegistryPackages.new
        .publish("github.com/kemalcr/kemal", "kemal", ["1.9.0", "1.10.0"])
        .install

      response = get.call(kemal)

      response.status_code.should eq(302)
      response.headers["Location"].should eq("#{kemal}/1.10.0")
    end

    it "never lands on a withdrawn release" do
      StubRegistryPackages.new
        .publish("github.com/kemalcr/kemal", "kemal", ["1.6.0", "1.7.0"], yanked: ["1.7.0"])
        .install

      get.call(kemal).headers["Location"].should eq("#{kemal}/1.6.0")
    end

    it "404s for a repository the registry does not have" do
      StubRegistryPackages.install

      get.call("/docs/_/github.com/nobody/invented").status_code.should eq(404)
    end
  end

  describe "when the registry cannot be reached" do
    it "still serves documentation this app already holds" do
      doc = DocFactory.create &.package_name("github.com/kemalcr/kemal").current_version("1.6.0")
      DocVersionFactory.create &.doc_id(doc.id).version("1.6.0")
      StubRegistryPackages.new(reachable: false).install
      StubDocsStorage.holding.install

      response = get.call("#{kemal}/1.6.0")

      response.status_code.should eq(200)
    end

    it "registers nothing, because there is nothing to register from" do
      StubRegistryPackages.new(reachable: false).install
      StubDocsStorage.empty.install

      get.call("#{kemal}/1.6.0").status_code.should eq(404)

      DocQuery.new.select_count.should eq(0)
    end
  end

  describe "the bare name URLs that are already indexed" do
    it "keeps serving a package this app holds and the registry does not" do
      doc = DocFactory.create &.package_name("crystal").current_version("1.21.0")
      DocVersionFactory.create &.doc_id(doc.id).version("1.21.0")
      StubRegistryPackages.install
      StubDocsStorage.holding.install

      response = get.call("/docs/crystal/1.21.0")

      response.status_code.should eq(200)
      response.body.should contain("Version:")
    end

    it "sends a name with one owner to that repository" do
      StubRegistryPackages.new.publish("github.com/kemalcr/kemal", "kemal", ["1.6.0"]).install

      response = get.call("/docs/kemal/1.6.0")

      response.status_code.should eq(301)
      response.headers["Location"].should eq("#{kemal}/1.6.0")
    end

    it "sends a bare package URL to that repository too" do
      StubRegistryPackages.new.publish("github.com/kemalcr/kemal", "kemal", ["1.6.0"]).install

      response = get.call("/docs/kemal")

      response.status_code.should eq(301)
      response.headers["Location"].should eq(kemal)
    end

    it "404s a name no repository publishes" do
      StubRegistryPackages.install

      get.call("/docs/never-existed/1.0.0").status_code.should eq(404)
    end
  end

  # A README's relative image or link means a path in the repository this
  # version was published from, not a path on this origin, and only the
  # commit the artifact was actually built from can say where that path
  # lives: the registry stores "1.2.3" while the repository's own tag is
  # routinely "v1.2.3", and either string 404s against GitHub as often as
  # it resolves. `render_readme` reads `doc_versions.source_commit_sha` for
  # exactly this reason, not the version string either page already had.
  describe "resolving a repository-relative README reference" do
    it "uses the commit the artifact was built from, not the registered version string" do
      StubRegistryPackages.new
        .publish("github.com/acme/widget", "widget", ["1.2.3"],
          commit_shas: {"1.2.3" => "abc123deadbeef01"})
        .install

      document = {
        repository_name: "acme/widget",
        body:            "![logo](doc/logo.svg)",
        program:         {
          full_name: "Top Level Namespace",
          name:      "Top Level Namespace",
          kind:      "module",
          types:     [] of String,
        },
      }.to_json

      StubDocsStorage.holding(document).install

      response = get.call("/docs/_/github.com/acme/widget/1.2.3")

      response.status_code.should eq(200)
      response.body.should contain(
        "https://raw.githubusercontent.com/acme/widget/abc123deadbeef01/doc/logo.svg"
      )
      # Neither version string, so a reader cannot end up here by luck: the
      # host qualified path shows the sha won and nothing else.
      response.body.should_not contain("raw.githubusercontent.com/acme/widget/1.2.3/")
      response.body.should_not contain("raw.githubusercontent.com/acme/widget/v1.2.3/")
    end

    it "drops a relative image when no commit has been recorded for the version" do
      doc = DocFactory.create &.package_name("github.com/acme/nosha")
      DocVersionFactory.create &.doc_id(doc.id).version("1.0.0").source_commit_sha(nil)

      document = {
        repository_name: "acme/nosha",
        body:            "![logo](doc/logo.svg)",
        program:         {
          full_name: "Top Level Namespace",
          name:      "Top Level Namespace",
          kind:      "module",
          types:     [] of String,
        },
      }.to_json

      # Registry unreachable, so the row already held is what serves the
      # page: exactly the state a version built before this column existed
      # is in, and the one this spec exists to keep honest.
      StubRegistryPackages.new(reachable: false).install
      StubDocsStorage.holding(document).install

      response = get.call("/docs/_/github.com/acme/nosha/1.0.0")

      response.status_code.should eq(200)
      response.body.should_not contain("<img")
    end
  end
end
