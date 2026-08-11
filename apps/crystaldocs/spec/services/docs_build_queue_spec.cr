require "../spec_helper"

# The docs build queue crosses an app boundary, and it crosses it untyped:
# JoobQ writes a job as a bare JSON object with no type tag onto a Redis list,
# and crystalshards pops it into a typed Queue(BuildDocsWorker). Nothing in
# either compiler run checks that those two structs agree.
#
# So the wire format is the contract, and this is the guard on it. If someone
# renames a field here, or crystalshards renames one there, these examples are
# the only thing between that and jobs that vanish into a parse error at
# three in the morning.
describe CrystalDocs::DocsBuildJob do
  job = -> { CrystalDocs::DocsBuildJob.new(shard_name: "kemal", version: "1.6.0") }

  it "goes to the docs queue, which is the list crystalshards pops" do
    job.call.queue.should eq("docs")
    CrystalDocs::DocsBuildQueue::QUEUE.should eq("docs")
  end

  # BuildDocsWorker's initialize is `(@shard_name : String, @version : String)`,
  # and JSON::Serializable serialises ivars by name. These two keys are the
  # entire payload as far as the builder is concerned.
  it "carries shard_name and version, spelled exactly as the consumer's ivars" do
    parsed = JSON.parse(job.call.to_json)

    parsed["shard_name"].as_s.should eq("kemal")
    parsed["version"].as_s.should eq("1.6.0")
  end

  it "names the package shard_name, because that is the consumer's field" do
    keys = JSON.parse(job.call.to_json).as_h.keys

    keys.should contain("shard_name")
    keys.should_not contain("package_name")
  end

  # The envelope comes from JoobQ's own mixin rather than being hand written,
  # which is the point: status serialises lowercase, and a hand rolled payload
  # would reasonably have guessed "Enqueued" and produced something the
  # consumer cannot parse.
  it "carries the JoobQ envelope the consumer expects to find" do
    parsed = JSON.parse(job.call.to_json).as_h

    %w[jid queue retries max_retries expires status error].each do |field|
      parsed.has_key?(field).should be_true
    end
  end

  it "serialises status in the form JoobQ itself parses" do
    JSON.parse(job.call.to_json)["status"].as_s.should eq("enqueued")
  end

  it "gives every job a distinct id" do
    job.call.jid.should_not eq(job.call.jid)
  end

  # A crystaldocs process must never run a docs build: it would clone a
  # repository and compile third party code inside the web app.
  it "refuses to perform work in this app" do
    expect_raises(Exception, /performed by crystalshards/) do
      job.call.perform
    end
  end
end

describe CrystalDocs::DocsBuildQueue do
  it "builds the real JoobQ backed queue by default" do
    CrystalDocs::DocsBuildQueue.override = nil

    CrystalDocs::DocsBuildQueue.build.should be_a(CrystalDocs::JoobQDocsBuildQueue)
  end

  it "uses the override when one is installed" do
    queue = RecordingBuildQueue.install

    CrystalDocs::DocsBuildQueue.build.should be(queue)
  end
end
