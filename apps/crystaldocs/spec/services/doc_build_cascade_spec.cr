require "../spec_helper"

# Commissioning one version is also the moment we learn what else has to be
# documented before that version's page is any good. A cross link only becomes
# a link when the owning package has a version with a successful build, so a
# reader on kemal sees `Radix::Tree` as plain text until radix is documented,
# and reading kemal again never changes that.
#
# Every example here is about which combinations get commissioned and how many
# times, because that is the whole contract: too few and the links stay dead,
# too many and one page view spends compute on a graph nobody asked for.
describe "CrystalDocs::DocBuildRequests dependency cascade" do
  requests = ->(queue : CrystalDocs::DocsBuildQueue) {
    CrystalDocs::DocBuildRequests.new(queue)
  }

  # A core version this app has already built. The cascade skips the standard
  # library when one it holds already satisfies the requirement, so an example
  # about commissioning core has to start from a site that holds none.
  document_core = ->(version : String) {
    doc = DocFactory.create &.package_name(CrystalDocs::CORE_PACKAGE).current_version(version)
    DocVersionFactory.create &.doc_id(doc.id)
      .version(version)
      .build_status("success")
      .storage_path("#{CrystalDocs::CORE_PACKAGE}/#{version}")
  }

  describe "the dependencies a release declared" do
    it "commissions each of them at the release the parent resolves to" do
      queue = RecordingBuildQueue.new
      StubRegistryPackages.install.declares(
        "github.com/kemalcr/kemal", "1.12.0",
        dependencies: {
          "github.com/luislavena/radix"     => "0.4.1",
          "github.com/crystal-loot/ex_page" => "0.5.0",
        }
      )

      requests.call(queue).request_with_dependencies("github.com/kemalcr/kemal", "1.12.0")

      queue.count_for("github.com/luislavena/radix", "0.4.1").should eq(1)
      queue.count_for("github.com/crystal-loot/ex_page", "0.5.0").should eq(1)
    end

    it "still commissions the version the reader asked for" do
      queue = RecordingBuildQueue.new
      StubRegistryPackages.install.declares(
        "github.com/kemalcr/kemal", "1.12.0",
        dependencies: {"github.com/luislavena/radix" => "0.4.1"}
      )

      request = requests.call(queue).request_with_dependencies("github.com/kemalcr/kemal", "1.12.0")

      request.package_name.should eq("github.com/kemalcr/kemal")
      request.version.should eq("1.12.0")
      queue.count_for("github.com/kemalcr/kemal", "1.12.0").should eq(1)
    end

    # Direct only is the decision, so exactly one level is commissioned per
    # call. The closure fills in as each dependency is itself commissioned; it
    # does not arrive in one request, and a spec that let it would be
    # asserting a graph walk on a reader's page load.
    it "does not walk past the first level" do
      queue = RecordingBuildQueue.new
      StubRegistryPackages.install
        .declares("app", "1.0.0", dependencies: {"middle" => "2.0.0"})
        .declares("middle", "2.0.0", dependencies: {"bottom" => "3.0.0"})

      requests.call(queue).request_with_dependencies("app", "1.0.0")

      queue.count_for("middle", "2.0.0").should eq(1)
      queue.count_for("bottom", "3.0.0").should eq(0)
    end

    # The other half of the same decision: one more level is reached every
    # time something is commissioned, so the closure completes over successive
    # requests rather than never.
    it "reaches the next level when that dependency is itself commissioned" do
      queue = RecordingBuildQueue.new
      registry = StubRegistryPackages.install
        .declares("app", "1.0.0", dependencies: {"middle" => "2.0.0"})
        .declares("middle", "2.0.0", dependencies: {"bottom" => "3.0.0"})
      registry.should_not be_nil

      service = requests.call(queue)
      service.request_with_dependencies("app", "1.0.0")
      service.request_with_dependencies("middle", "2.0.0")

      queue.count_for("bottom", "3.0.0").should eq(1)
    end
  end

  describe "a dependency that is already built" do
    it "is not commissioned again" do
      queue = RecordingBuildQueue.new
      DocBuildRequestFactory.create &.package_name("github.com/luislavena/radix")
        .version("0.4.1")
        .succeeded
      StubRegistryPackages.install.declares(
        "github.com/kemalcr/kemal", "1.12.0",
        dependencies: {"github.com/luislavena/radix" => "0.4.1"}
      )

      requests.call(queue).request_with_dependencies("github.com/kemalcr/kemal", "1.12.0")

      queue.count_for("github.com/luislavena/radix", "0.4.1").should eq(0)
      queue.count_for("github.com/kemalcr/kemal", "1.12.0").should eq(1)
    end

    it "leaves the succeeded row alone rather than resetting it" do
      queue = RecordingBuildQueue.new
      DocBuildRequestFactory.create &.package_name("github.com/luislavena/radix")
        .version("0.4.1")
        .succeeded(3.hours.ago)
      StubRegistryPackages.install.declares(
        "github.com/kemalcr/kemal", "1.12.0",
        dependencies: {"github.com/luislavena/radix" => "0.4.1"}
      )

      requests.call(queue).request_with_dependencies("github.com/kemalcr/kemal", "1.12.0")

      radix = CrystalDocs::DocBuildRequests.new(queue).find("github.com/luislavena/radix", "0.4.1")
      radix.not_nil!.status.should eq(DocBuildRequest::SUCCEEDED)
      radix.not_nil!.attempts.should eq(1)
    end
  end

  # The graph has cycles in it. Two shards that depend on each other, and a
  # shard that lists itself, both terminate here, and neither needs a visited
  # set: there is no recursion, and a combination that is already claimed
  # commissions nothing.
  describe "a dependency cycle" do
    it "commissions each side exactly once, whichever end a reader arrives at" do
      queue = RecordingBuildQueue.new
      StubRegistryPackages.install
        .declares("left", "1.0.0", dependencies: {"right" => "2.0.0"})
        .declares("right", "2.0.0", dependencies: {"left" => "1.0.0"})

      service = requests.call(queue)
      service.request_with_dependencies("left", "1.0.0")
      service.request_with_dependencies("right", "2.0.0")

      queue.count_for("left", "1.0.0").should eq(1)
      queue.count_for("right", "2.0.0").should eq(1)
      queue.enqueued.size.should eq(2)
    end

    it "does not grow with the number of times the cycle is re-entered" do
      queue = RecordingBuildQueue.new
      StubRegistryPackages.install
        .declares("left", "1.0.0", dependencies: {"right" => "2.0.0"})
        .declares("right", "2.0.0", dependencies: {"left" => "1.0.0"})

      service = requests.call(queue)
      10.times do
        service.request_with_dependencies("left", "1.0.0")
        service.request_with_dependencies("right", "2.0.0")
      end

      queue.enqueued.size.should eq(2)
    end

    it "terminates on a shard that depends on itself" do
      queue = RecordingBuildQueue.new
      StubRegistryPackages.install.declares(
        "recursive", "1.0.0",
        dependencies: {"recursive" => "1.0.0"}
      )

      requests.call(queue).request_with_dependencies("recursive", "1.0.0")

      queue.count_for("recursive", "1.0.0").should eq(1)
    end
  end

  describe "the standard library" do
    it "commissions the Crystal version the release targets" do
      queue = RecordingBuildQueue.new
      StubRegistryPackages.install.declares(
        "github.com/kemalcr/kemal", "1.12.0",
        crystal: ">= 1.12.0"
      )

      requests.call(queue).request_with_dependencies("github.com/kemalcr/kemal", "1.12.0")

      queue.count_for(CrystalDocs::CORE_PACKAGE, "1.12.0").should eq(1)
    end

    # The registry stores this column as a requirement, and a plain version is
    # one of the shapes it really holds.
    it "reads an exactly pinned Crystal as that version" do
      queue = RecordingBuildQueue.new
      StubRegistryPackages.install.declares("kemal", "1.4.0", crystal: "1.2.0")

      requests.call(queue).request_with_dependencies("kemal", "1.4.0")

      queue.count_for(CrystalDocs::CORE_PACKAGE, "1.2.0").should eq(1)
    end

    it "takes the lower bound of a pessimistic requirement" do
      queue = RecordingBuildQueue.new
      StubRegistryPackages.install.declares("shard", "1.0.0", crystal: "~> 1.6")

      requests.call(queue).request_with_dependencies("shard", "1.0.0")

      queue.count_for(CrystalDocs::CORE_PACKAGE, "1.6.0").should eq(1)
    end

    # `DependencyIndex` links core names to the highest core version with a
    # successful build that satisfies the reader's requirement. Once one
    # exists the links already resolve, so a second build lower down the range
    # would be selected by nothing and is a compile spent on nothing.
    it "commissions nothing when a version we already hold satisfies" do
      queue = RecordingBuildQueue.new
      document_core.call("1.21.0")
      StubRegistryPackages.install.declares("shard", "1.0.0", crystal: ">= 1.12.0")

      requests.call(queue).request_with_dependencies("shard", "1.0.0")

      queue.enqueued.map(&.package_name).should_not contain(CrystalDocs::CORE_PACKAGE)
    end

    it "commissions one when the version we hold does not satisfy" do
      queue = RecordingBuildQueue.new
      document_core.call("1.4.0")
      StubRegistryPackages.install.declares("shard", "1.0.0", crystal: ">= 1.12.0")

      requests.call(queue).request_with_dependencies("shard", "1.0.0")

      queue.count_for(CrystalDocs::CORE_PACKAGE, "1.12.0").should eq(1)
    end

    # A version that failed to build is not a version this site can link to,
    # so it cannot stand in for one that satisfies.
    it "ignores a core version whose build failed" do
      queue = RecordingBuildQueue.new
      doc = DocFactory.create &.package_name(CrystalDocs::CORE_PACKAGE).current_version("1.12.0")
      DocVersionFactory.create &.doc_id(doc.id)
        .version("1.12.0")
        .build_status("failed")
        .storage_path("crystal/1.12.0")
      StubRegistryPackages.install.declares("shard", "1.0.0", crystal: ">= 1.12.0")

      requests.call(queue).request_with_dependencies("shard", "1.0.0")

      queue.count_for(CrystalDocs::CORE_PACKAGE, "1.12.0").should eq(1)
    end

    it "commissions nothing for a release that declared no Crystal" do
      queue = RecordingBuildQueue.new
      StubRegistryPackages.install.declares("shard", "1.0.0", crystal: nil)

      requests.call(queue).request_with_dependencies("shard", "1.0.0")

      queue.enqueued.map(&.package_name).should_not contain(CrystalDocs::CORE_PACKAGE)
    end

    # "*" and a bare ceiling name no release we could commit to, and guessing
    # one is how this would start compiling arbitrary compilers.
    it "commissions nothing for a requirement with no lower bound" do
      queue = RecordingBuildQueue.new
      StubRegistryPackages.install
        .declares("unpinned", "1.0.0", crystal: "*")
        .declares("capped", "1.0.0", crystal: "< 2.0.0")

      service = requests.call(queue)
      service.request_with_dependencies("unpinned", "1.0.0")
      service.request_with_dependencies("capped", "1.0.0")

      queue.enqueued.map(&.package_name).should_not contain(CrystalDocs::CORE_PACKAGE)
    end
  end

  # The parent is what the reader asked for. Everything else on this path is
  # our inference about what they will want next, and an inference must not be
  # able to fail the thing it was inferred from.
  describe "when the registry cannot answer" do
    it "commissions the parent for a package the registry has never heard of" do
      queue = RecordingBuildQueue.new
      StubRegistryPackages.install

      request = requests.call(queue).request_with_dependencies("unknown", "1.0.0")

      request.status.should eq(DocBuildRequest::PENDING)
      queue.count_for("unknown", "1.0.0").should eq(1)
    end

    it "commissions the parent when the registry is unreachable" do
      queue = RecordingBuildQueue.new
      registry = StubRegistryPackages.install.declares(
        "github.com/kemalcr/kemal", "1.12.0",
        dependencies: {"github.com/luislavena/radix" => "0.4.1"}
      )
      registry.reachable = false

      requests.call(queue).request_with_dependencies("github.com/kemalcr/kemal", "1.12.0")

      queue.count_for("github.com/kemalcr/kemal", "1.12.0").should eq(1)
      queue.count_for("github.com/luislavena/radix", "0.4.1").should eq(0)
    end

    it "commissions the parent when reading the registry raises" do
      queue = RecordingBuildQueue.new
      CrystalDocs::RegistryPackages.provider = -> { RaisingRegistryPackages.new.as(CrystalDocs::RegistryPackages) }

      begin
        request = requests.call(queue).request_with_dependencies("github.com/kemalcr/kemal", "1.12.0")

        request.status.should eq(DocBuildRequest::PENDING)
        queue.count_for("github.com/kemalcr/kemal", "1.12.0").should eq(1)
      ensure
        CrystalDocs::RegistryPackages.provider = nil
      end
    end

    # A dependency the registry never resolved to a repository has no release
    # list and no key to address a page by, so there is nothing to commission
    # for it. The rest of the declaration is unaffected.
    it "commissions the dependencies it does know" do
      queue = RecordingBuildQueue.new
      StubRegistryPackages.install.declares(
        "github.com/kemalcr/kemal", "1.12.0",
        crystal: ">= 1.12.0",
        dependencies: {"github.com/luislavena/radix" => "0.4.1"}
      )

      requests.call(queue).request_with_dependencies("github.com/kemalcr/kemal", "1.12.0")

      queue.count_for("github.com/luislavena/radix", "0.4.1").should eq(1)
      queue.count_for(CrystalDocs::CORE_PACKAGE, "1.12.0").should eq(1)
      queue.count_for("github.com/kemalcr/kemal", "1.12.0").should eq(1)
    end
  end
end

# A registry that fails mid-request, which is a different failure from one that
# was never configured: `declaration` does not rescue, on purpose, so the
# rescue that protects the parent has to be the one on the cascade.
private class RaisingRegistryPackages < CrystalDocs::RegistryPackages
  def declaration(package_key : String, version : String) : CrystalDocs::RegistryPackages::Declaration
    raise "the registry connection dropped"
  end
end
