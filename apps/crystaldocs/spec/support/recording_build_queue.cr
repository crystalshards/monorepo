# Counts enqueues instead of commissioning real builds.
#
# The point of every build-request example is how many builds were
# commissioned, so the queue has to be observable. Reaching a real Cloud Tasks
# queue would also make the suite depend on a Google project being reachable
# to prove a database constraint, which it does not.
class RecordingBuildQueue < CrystalDocs::DocsBuildQueue
  record Enqueued, package_name : String, version : String

  getter enqueued = [] of Enqueued

  # Simulates a queue that cannot be reached, so the "queue was never told"
  # path is exercised rather than assumed.
  property? available : Bool = true

  def enqueue(package_name : String, version : String) : String?
    return nil unless available?

    enqueued << Enqueued.new(package_name, version)
    "job-#{enqueued.size}"
  end

  def count_for(package_name : String, version : String) : Int32
    enqueued.count { |job| job.package_name == package_name && job.version == version }
  end

  # Installs a fresh recorder for one example and hands it back.
  def self.install : RecordingBuildQueue
    queue = new
    CrystalDocs::DocsBuildQueue.override = queue
    queue
  end
end

# Every example gets a fresh recorder, whether or not it asked for one.
#
# Without this, any example that renders an unbuilt version through the real
# action reaches the real producer and commissions a build. That is how
# `test-package 1.0.0` ended up on the live docs queue during a spec run. A
# suite must not be able to commission real builds, so the default is a
# recorder and reaching the real queue takes a deliberate override inside an
# example.
#
# before_each rather than an after_each reset, deliberately. Installing at the
# start of every example guarantees the state an example begins in, which is
# the thing that matters; an after_each that nils the override would instead
# leave the REAL queue installed in the gaps between examples, which is the
# arrangement that leaked in the first place. An example is free to nil the
# override to assert on the default wiring, because the next example gets a
# recorder again regardless.
Spec.before_each do
  RecordingBuildQueue.install
end
