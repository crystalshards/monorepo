require "joobq"

module CrystalDocs
  # Producer side of the documentation build queue.
  #
  # The builder itself lives in crystalshards (`BuildDocsWorker`, JoobQ queue
  # "docs"), because that is where the sandbox, the repository clones and the
  # storage credentials already are. This app never builds; it only asks.
  #
  # Interop is by field rather than by class. JoobQ serialises a job as a bare
  # JSON object with no type tag and pushes it onto a Redis list named after
  # the queue; the consumer is a typed `Queue(BuildDocsWorker)` that parses
  # whatever it pops. So the real contract is "an object on the `docs` list
  # carrying shard_name and version", and this struct is that object. Going
  # through JoobQ's own Job mixin instead of hand building the JSON means the
  # envelope fields (jid, queue, retries, max_retries, expires, status) cannot
  # drift away from what the consumer expects to parse.
  struct DocsBuildJob
    include JoobQ::Job

    # Named shard_name, not package_name, because the consumer's ivar is
    # shard_name and the field names are the wire format.
    getter shard_name : String
    getter version : String

    def initialize(@shard_name : String, @version : String)
      @queue = DocsBuildQueue::QUEUE
    end

    # Required by the mixin. This process is a producer; if this ever runs it
    # means a crystaldocs process was configured as a JoobQ worker, which
    # would try to clone and compile third party code inside the web app.
    def perform
      raise "DocsBuildJob is enqueued by crystaldocs and performed by crystalshards. crystaldocs must not run the docs queue: building clones a repository and compiles untrusted code, which does not belong in a web process."
    end
  end

  # Somewhere to send a build request, and a seam to substitute in specs.
  abstract class DocsBuildQueue
    QUEUE = "docs"

    class_property override : DocsBuildQueue? = nil

    def self.build : DocsBuildQueue
      @@override || JoobQDocsBuildQueue.new
    end

    # Returns the queued job's id, or nil when the queue could not be reached.
    # Nil is not a failure of the build; it means the request was never
    # delivered, and the caller decides what to tell the reader.
    abstract def enqueue(package_name : String, version : String) : String?
  end

  class JoobQDocsBuildQueue < DocsBuildQueue
    def enqueue(package_name : String, version : String) : String?
      job = DocsBuildJob.new(shard_name: package_name, version: version)
      JoobQ.add(job)
      job.jid.to_s
    rescue ex : Exception
      # Redis being down must not turn a docs page into a 500. The row stays
      # pending and the next reader after the retry floor tries again.
      Lucky::Log.dexter.warn do
        {docs_build_enqueue_failed: "#{package_name} #{version}", error: ex.message}
      end
      nil
    end
  end
end
