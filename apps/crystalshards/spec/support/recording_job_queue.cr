# Records what was dispatched instead of doing it.
#
# `IndexShardWorker.enqueue` now runs the job where it was called rather than
# handing it to a broker. That is right in production and wrong in a suite: an
# action example that happens to enqueue indexing would reach out to a shard's
# real git host, so the example's result would depend on GitHub being up and on
# whatever that repository looks like today.
#
# Before this, the same examples were protected by accident: `.enqueue` raised
# because the broker was not running, and every call site caught it. Removing
# the broker removed that accident, so the protection is deliberate here.
class RecordingJobQueue < CrystalShards::JobQueue
  record Dispatched, job : Symbol, shard_name : String, version : String

  getter dispatched = [] of Dispatched

  def index_shard(shard_name : String, version : String) : Nil
    @dispatched << Dispatched.new(:index_shard, shard_name, version)
  end

  def update_dependencies(shard_name : String, version : String) : Nil
    @dispatched << Dispatched.new(:update_dependencies, shard_name, version)
  end

  def build_docs(shard_name : String, version : String) : String?
    @dispatched << Dispatched.new(:build_docs, shard_name, version)
    "build-#{@dispatched.size}"
  end

  def count_for(job : Symbol) : Int32
    dispatched.count { |entry| entry.job == job }
  end

  def self.install : RecordingJobQueue
    queue = new
    CrystalShards::JobQueue.override = queue
    queue
  end
end

# Every example gets a fresh recorder, whether or not it asked for one.
#
# before_each rather than an after_each reset, deliberately: installing at the
# start of every example guarantees the state an example begins in. An
# after_each that nils the override would instead leave the real, inline queue
# installed in the gaps between examples, which is the arrangement that lets a
# stray dispatch escape.
#
# An example that wants the real behaviour nils the override itself, and the
# next example gets a recorder again regardless.
Spec.before_each do
  RecordingJobQueue.install
end
