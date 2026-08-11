require "../services/docs_build_queue"

module CrystalShards
  # How a decision to do background work becomes work actually happening.
  #
  # There are exactly two answers, and which one a job gets is a property of
  # the job rather than a configuration choice:
  #
  #   run it now      indexing and dependency resolution. Both are a handful
  #                   of database writes plus a read from the shard's host,
  #                   they execute no code from the shard, and they finish in
  #                   the time an HTTP request already allows.
  #
  #   Cloud Tasks     documentation builds. These compile third party code, so
  #                   they run in a Job with no credentials, they take minutes,
  #                   and the request that asked for one is long gone by the
  #                   time it finishes.
  #
  # There is no third answer and deliberately no general purpose queue. The
  # long-running worker that used to poll Redis is gone: on Cloud Run a
  # container gets no CPU once its response is written, so anything deferred
  # without a durable queue behind it is simply dropped. Running the cheap work
  # inline is not a compromise, it is the only arrangement where the caller
  # finds out whether it happened.
  abstract class JobQueue
    class_property override : JobQueue? = nil

    def self.current : JobQueue
      @@override ||= InlineJobQueue.new
    end

    abstract def index_shard(shard_name : String, version : String) : Nil
    abstract def update_dependencies(shard_name : String, version : String) : Nil
    abstract def build_docs(shard_name : String, version : String) : String?
  end

  class InlineJobQueue < JobQueue
    def index_shard(shard_name : String, version : String) : Nil
      IndexShardWorker.new(shard_name: shard_name, version: version).perform
    end

    def update_dependencies(shard_name : String, version : String) : Nil
      UpdateDependenciesWorker.new(shard_name: shard_name, version: version).perform
    end

    # The one kind of work that does not run here. A docs build compiles code
    # the shard author wrote, and this process holds the database and storage
    # credentials, so it goes to the launcher through Cloud Tasks and runs in a
    # Job that holds nothing.
    def build_docs(shard_name : String, version : String) : String?
      DocsBuildQueue.build.enqueue(shard_name, version)
    end
  end
end
