require "../../spec_helper"

# Documentation is built the first time a version is asked for. That makes the
# version route the one URL on this site that can commission compute, so these
# examples are about what a stranger with a URL bar can spend.
#
# The invariant, and it is the whole reason this is safe to expose: enqueue is
# keyed on (package, version) and never on the requested path. Spend is
# bounded by the number of real versions, not by the number of URLs anyone can
# type.
describe "building documentation on first request" do
  version_url = "/docs/lazy-pkg/1.0.0"

  planted = -> {
    doc = DocFactory.create &.package_name("lazy-pkg").current_version("1.0.0")
    DocVersionFactory.create &.doc_id(doc.id).version("1.0.0").build_status("pending")
    doc
  }

  get = ->(path : String) { BrowserClient.exec(Lucky::RouteHelper.new(:get, path)) }

  describe "a version that has never been built" do
    it "renders instead of erroring, and says a build is happening" do
      planted.call
      StubDocsStorage.empty.install
      RecordingBuildQueue.install

      response = get.call(version_url)

      response.status_code.should eq(200)
      response.body.should contain("Documentation is being built")
    end

    it "queues exactly one build" do
      planted.call
      StubDocsStorage.empty.install
      queue = RecordingBuildQueue.install

      get.call(version_url)

      queue.count_for("lazy-pkg", "1.0.0").should eq(1)
    end

    # The acceptance case. Nothing caches a miss, so this is what a reader
    # sitting on the page with auto refresh actually generates.
    it "queues one build however many times it is requested" do
      planted.call
      StubDocsStorage.empty.install
      queue = RecordingBuildQueue.install

      6.times { get.call(version_url) }

      queue.enqueued.size.should eq(1)
      DocBuildRequestQuery.new.package_name("lazy-pkg").version("1.0.0").select_count.should eq(1)
    end

    it "asks the browser to come back, so the page fills in on its own" do
      planted.call
      StubDocsStorage.empty.install
      RecordingBuildQueue.install

      response = get.call(version_url)

      response.headers["Refresh"]?.should eq(Docs::LazyBuild::REFRESH_SECONDS.to_s)
    end

    # The switcher and the build badge are how a reader moves between versions
    # and learns a build failed. An earlier revision routed this state to its
    # own page and lost both.
    it "keeps the version switcher and the build badge" do
      planted.call
      StubDocsStorage.empty.install
      RecordingBuildQueue.install

      response = get.call(version_url)

      response.body.should contain("Version:")
      response.body.should contain("Build:")
    end
  end

  describe "a version that is already built" do
    it "renders the documentation" do
      planted.call
      StubDocsStorage.holding.install
      RecordingBuildQueue.install

      response = get.call(version_url)

      response.status_code.should eq(200)
      response.body.should contain("lazy-pkg")
    end

    it "queues nothing" do
      planted.call
      StubDocsStorage.holding.install
      queue = RecordingBuildQueue.install

      3.times { get.call(version_url) }

      queue.enqueued.should be_empty
    end

    it "registers no build request at all" do
      planted.call
      StubDocsStorage.holding.install
      RecordingBuildQueue.install

      get.call(version_url)

      DocBuildRequestQuery.new.package_name("lazy-pkg").select_count.should eq(0)
    end

    it "does not ask the browser to refresh" do
      planted.call
      StubDocsStorage.holding.install
      RecordingBuildQueue.install

      response = get.call(version_url)

      response.headers["Refresh"]?.should be_nil
    end
  end

  describe "a version whose build recently failed" do
    it "does not queue another build" do
      planted.call
      DocBuildRequestFactory.create &.package_name("lazy-pkg").version("1.0.0")
        .failed(2.minutes.ago)
      StubDocsStorage.empty.install
      queue = RecordingBuildQueue.install

      get.call(version_url)

      queue.enqueued.should be_empty
    end

    it "does not queue a build however many times the page is reloaded" do
      planted.call
      DocBuildRequestFactory.create &.package_name("lazy-pkg").version("1.0.0")
        .failed(10.minutes.ago)
      StubDocsStorage.empty.install
      queue = RecordingBuildQueue.install

      8.times { get.call(version_url) }

      queue.enqueued.should be_empty
    end

    it "shows the reader that the build failed, and what the builder said" do
      planted.call
      DocBuildRequestFactory.create &.package_name("lazy-pkg").version("1.0.0")
        .failed(2.minutes.ago, "undefined constant Foo")
      StubDocsStorage.empty.install
      RecordingBuildQueue.install

      response = get.call(version_url)

      response.body.should contain("Documentation could not be built")
      response.body.should contain("undefined constant Foo")
    end

    it "does not auto refresh a failure" do
      planted.call
      DocBuildRequestFactory.create &.package_name("lazy-pkg").version("1.0.0")
        .failed(2.minutes.ago)
      StubDocsStorage.empty.install
      RecordingBuildQueue.install

      response = get.call(version_url)

      response.headers["Refresh"]?.should be_nil
    end

    it "queues one build once the retry floor has passed" do
      planted.call
      DocBuildRequestFactory.create &.package_name("lazy-pkg").version("1.0.0")
        .failed(CrystalDocs::DocBuildRequests::RETRY_FLOOR.ago - 1.minute)
      StubDocsStorage.empty.install
      queue = RecordingBuildQueue.install

      get.call(version_url)

      queue.count_for("lazy-pkg", "1.0.0").should eq(1)
    end
  end

  describe "when the documentation store cannot be reached" do
    it "queues nothing, because a build cannot fix a store that is down" do
      planted.call
      StubDocsStorage.unreachable.install
      queue = RecordingBuildQueue.install

      get.call(version_url)

      queue.enqueued.should be_empty
      DocBuildRequestQuery.new.package_name("lazy-pkg").select_count.should eq(0)
    end

    it "says so rather than claiming the version was never documented" do
      planted.call
      StubDocsStorage.unreachable.install
      RecordingBuildQueue.install

      response = get.call(version_url)

      response.status_code.should eq(200)
      response.body.should contain("Documentation could not be loaded")
    end
  end

  # Everything below is about the version route being a spend endpoint.
  describe "spend is bounded by real versions, not by URLs" do
    # A crawler walking invented type paths under one unbuilt version must not
    # multiply builds. It cannot: the type route never enqueues, and the
    # version it redirects to is a single (package, version) key.
    it "commissions one build for a crawler walking many invented type paths" do
      planted.call
      StubDocsStorage.empty.install
      queue = RecordingBuildQueue.install

      %w[Evil Evil/Nested Made/Up/Path Another cccc].each do |invented|
        get.call("#{version_url}/#{invented}")
      end
      get.call(version_url)

      queue.enqueued.size.should eq(1)
    end

    it "never returns 200 for an invented type path on an unbuilt version" do
      planted.call
      StubDocsStorage.empty.install
      RecordingBuildQueue.install

      response = get.call("#{version_url}/Evil/Nested")

      response.status_code.should_not eq(200)
    end

    it "queues nothing from a type path on its own account" do
      planted.call
      StubDocsStorage.empty.install
      queue = RecordingBuildQueue.install

      get.call("#{version_url}/Evil/Nested")

      queue.enqueued.should be_empty
    end

    # A bot is just a request. The bound is the unique constraint, not
    # anything about who is asking, so there is no user agent that gets a
    # different answer.
    it "applies the same bound to a declared bot" do
      planted.call
      StubDocsStorage.empty.install
      queue = RecordingBuildQueue.install

      4.times do
        BrowserClient.new
          .headers("User-Agent": "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)")
          .exec(Lucky::RouteHelper.new(:get, version_url))
      end

      queue.enqueued.size.should eq(1)
    end

    it "applies the same bound to HEAD requests" do
      planted.call
      StubDocsStorage.empty.install
      queue = RecordingBuildQueue.install

      4.times { BrowserClient.exec(Lucky::RouteHelper.new(:head, version_url)) }
      get.call(version_url)

      queue.enqueued.size.should eq(1)
    end

    it "counts each real version separately, because each is real work" do
      doc = DocFactory.create &.package_name("lazy-pkg").current_version("2.0.0")
      DocVersionFactory.create &.doc_id(doc.id).version("1.0.0").build_status("pending")
      DocVersionFactory.create &.doc_id(doc.id).version("2.0.0").build_status("pending")
      StubDocsStorage.empty.install
      queue = RecordingBuildQueue.install

      get.call("/docs/lazy-pkg/1.0.0")
      get.call("/docs/lazy-pkg/2.0.0")

      queue.enqueued.size.should eq(2)
    end
  end
end
