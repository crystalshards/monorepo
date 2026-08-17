require "../../spec_helper"

# What a reader watching a running build is shown.
#
# The page reloads itself every few seconds while a build is in flight, and
# before this it redrew the same sentence every time. A build that clones,
# resolves, installs and compiles is minutes on a large shard, and one
# unchanging line for all of it reads exactly like a stuck queue.
private def get(url : String)
  BrowserClient.exec(Lucky::RouteHelper.new(:get, url))
end

private def building_at(step : String?)
  DocFactory.create &.package_name("prog-pkg")
  DocVersionFactory.create &.doc_id(DocQuery.new.package_name("prog-pkg").first.id)
    .version("1.0.0")
    .build_status("building")

  DocBuildRequestFactory.create &.package_name("prog-pkg")
    .version("1.0.0")
    .status(DocBuildRequest::BUILDING)
    .started_at(1.minute.ago)
    .step(step)

  StubDocsStorage.empty.install
  RecordingBuildQueue.install

  get("/docs/prog-pkg/1.0.0")
end

describe "build progress" do
  it "lists every step from the start, so the list does not grow under the reader" do
    response = building_at("cloning")

    response.status_code.should eq(200)

    CrystalDocs::BuildSteps::ALL.each do |step|
      response.body.should contain(step.label)
    end
  end

  it "marks the reported step as current and the ones before it as done" do
    response = building_at("dependencies")

    # The whole progress claim, in one assertion: which steps are behind the
    # build, which one it is on, and which are still ahead, in builder order.
    states = response.body.scan(/build-step (is-[a-z]+)/).map(&.[1])

    states.should eq(["is-done", "is-done", "is-current", "is-waiting", "is-waiting"])
  end

  it "marks nothing done when the build has not reported a step yet" do
    # The first seconds of every build, and the permanent state of one whose
    # step writes were all lost. The list is shown; no progress is invented.
    response = building_at(nil)

    response.body.should contain("Cloning")
    response.body.should_not contain("is-done")
    response.body.should_not contain("is-current")
  end

  it "shows a step name it does not recognise rather than dropping it" do
    # crystalshards is a separate deployment and can be ahead of this one.
    CrystalDocs::BuildSteps.label_for("polishing").should eq("polishing")
    CrystalDocs::BuildSteps.index_of("polishing").should be_nil
  end

  it "knows the vocabulary crystalshards writes" do
    # If these drift, a reader watches a list where nothing is ever current.
    # The writer's copy is CrystalShards::DocsBuildStatus::Step.
    CrystalDocs::BuildSteps::ALL.map(&.name).should eq(
      ["cloning", "resolving", "dependencies", "documenting", "uploading"]
    )
  end
end
