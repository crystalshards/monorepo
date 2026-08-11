# One row per git host, holding everything needed to answer two questions: how
# far did the last sweep get, and can its result be trusted as complete.
#
# A crawl that stops halfway is worse than no crawl, because the registry then
# looks complete and is not. So a sweep persists its cursor after every page and
# records why it stopped, and anything short of an exhaustive pass is recorded
# as `partial` rather than as success.
class CrawlState < BaseModel
  # Status is the answer to "can I trust the last sweep".
  #
  #   idle       never run, or reset
  #   running    a sweep is in progress
  #   completed  finished, and the enumeration it used can see every shard
  #   partial    finished or stopped without covering the host
  #   failed     stopped on an error or a missing token, nothing to trust
  module Status
    IDLE      = "idle"
    RUNNING   = "running"
    COMPLETED = "completed"
    PARTIAL   = "partial"
    FAILED    = "failed"
  end

  # Why the sweep is not running any more. Kept separate from status because
  # "stopped because the host rate limited us" and "stopped because it finished"
  # are both non-failures that mean very different things for coverage.
  module StopReason
    # Finished, and the enumeration it used can see every shard on the host.
    COMPLETED_EXHAUSTIVE = "completed_exhaustive"
    # Finished everything it could ask for, which is less than the whole host:
    # this host is enumerated by topic, so untagged repositories are invisible.
    COMPLETED_TOPIC_SCOPED = "completed_topic_scoped"
    # Ran to the end, but a search window held more results than the host would
    # return and could not be narrowed further, so some are unreachable.
    RESULT_CAP_TRUNCATED = "result_cap_truncated"
    # Paused by the host. The cursor is saved and the next run continues.
    RATE_LIMITED = "rate_limited"
    # Stopped because this run hit its page budget, not because it ran out.
    INTERRUPTED = "interrupted"
    ERROR       = "error"
    # Refused to start: the host's token is not configured.
    TOKEN_MISSING = "token_missing"
    # Not a host this registry knows how to crawl.
    UNSUPPORTED_HOST = "unsupported_host"
  end

  table do
    column host : String
    column status : String
    # Opaque to everything but the crawler that wrote it. Each host encodes its
    # own position (a search window and page, a page number, a project id) as
    # JSON, so resuming is a matter of handing this string back.
    column cursor : String?
    column last_started_at : Time?
    column last_completed_at : Time?
    column stop_reason : String?
    column last_error : String?
    column discovered_count : Int64
    column updated_count : Int64
    column unavailable_count : Int64
    column skipped_count : Int64
    column failed_count : Int64
  end

  def running? : Bool
    status == Status::RUNNING
  end

  def resumable? : Bool
    !cursor.nil?
  end

  # True only when the last sweep both finished and used an enumeration that can
  # see every shard on the host. Everything else is partial coverage, whatever
  # the reason.
  def trustworthy? : Bool
    status == Status::COMPLETED && stop_reason == StopReason::COMPLETED_EXHAUSTIVE
  end

  def summary_line : String
    parts = [
      "#{host}: #{status}",
      "discovered #{discovered_count}",
      "updated #{updated_count}",
    ]
    parts << "unavailable #{unavailable_count}" if unavailable_count > 0
    parts << "skipped #{skipped_count}" if skipped_count > 0
    parts << "failed #{failed_count}" if failed_count > 0
    parts << "stopped: #{stop_reason}" if stop_reason
    parts << "resumes from cursor" if resumable?
    parts.join(", ")
  end
end
