# A queue that will not take anything, the way a misconfigured Job's does.
#
# `CloudTasksConfig::Missing` is raised at enqueue time when an environment
# variable the queue path needs is absent, so every candidate in a run fails
# identically. This reproduces that shape without needing the real config.
class RefusingJobQueue < CrystalShards::JobQueue
  def index_shard(shard_name : String, version : String) : Nil
    raise "the queue is not configured"
  end

  def update_dependencies(shard_name : String, version : String) : Nil
    raise "the queue is not configured"
  end

  def build_docs(shard_name : String, version : String) : String?
    raise "GOOGLE_CLOUD_PROJECT is not set, so the queue path cannot be built"
  end

  def self.install : RefusingJobQueue
    queue = new
    CrystalShards::JobQueue.override = queue
    queue
  end
end
