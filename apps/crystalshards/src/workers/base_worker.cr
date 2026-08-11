require "../jobs/job_queue"

# A unit of background work.
#
# These used to be queued onto a broker and polled by a long-running worker
# process. There is no such process any more and no broker behind it: on Cloud
# Run a container gets no CPU once its response is written and scales to zero,
# so a poller either costs money doing nothing or is not running when work
# arrives. Each job now says how it is dispatched, through `JobQueue`, and
# there are only two answers: run it now, or hand it to Cloud Tasks.
#
# What is left here is the shape every job shares. `@queue` survives as a
# label because it is what the logs are grouped by, not because anything polls
# a list with that name.
abstract struct BaseJob
  getter queue : String = "default"

  protected def log_info(message : String)
    Log.info { "#{self.class.name}: #{message}" }
  end

  protected def log_error(message : String, exception : Exception? = nil)
    if exception
      Log.error(exception: exception) { "#{self.class.name}: #{message}" }
    else
      Log.error { "#{self.class.name}: #{message}" }
    end
  end
end
