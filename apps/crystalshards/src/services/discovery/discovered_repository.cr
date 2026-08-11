module Discovery
  # A repository a host's enumeration handed back, before anything has been
  # checked about it. It is a candidate: whether it is a shard is decided by
  # looking for a shard.yml at its root, not by anything in this record.
  record DiscoveredRepository,
    host : String,
    owner : String,
    repo : String,
    repository_url : String,
    description : String? = nil,
    homepage_url : String? = nil,
    default_branch : String? = nil,
    stars : Int32? = nil,
    forks : Int32? = nil do
    def slug : String
      "#{host}/#{owner}/#{repo}"
    end
  end

  # One page of an enumeration, plus where to resume.
  #
  # `next_cursor` nil means the enumeration is finished. That is the only signal
  # the engine uses to decide a sweep is complete, so a crawler must not return
  # nil while pages remain: doing so is exactly how a crawl reports success on
  # half a host.
  record CrawlPage,
    repositories : Array(DiscoveredRepository),
    next_cursor : String? = nil

  # What a sweep did. Counts are for the operator, and `status`/`stop_reason`
  # answer whether the result can be trusted as a complete view of the host.
  class CrawlReport
    getter host : String
    property status : String = CrawlState::Status::RUNNING
    property stop_reason : String? = nil
    property error : String? = nil
    property cursor : String? = nil
    property discovered : Int32 = 0
    property updated : Int32 = 0
    property unavailable : Int32 = 0
    property skipped : Int32 = 0
    property failed : Int32 = 0
    property pages : Int32 = 0
    property requests : Int32 = 0
    property waits : Int32 = 0
    getter started_at : Time
    property finished_at : Time? = nil

    def initialize(@host : String, @started_at : Time = Time.utc)
    end

    def complete? : Bool
      status == CrawlState::Status::COMPLETED
    end

    def partial? : Bool
      status == CrawlState::Status::PARTIAL
    end

    def failed? : Bool
      status == CrawlState::Status::FAILED
    end

    def to_s(io : IO) : Nil
      io << host << ": " << status
      io << " (" << stop_reason << ")" if stop_reason
      io << ", " << pages << " pages"
      io << ", " << requests << " requests"
      io << ", discovered " << discovered
      io << ", updated " << updated
      io << ", unavailable " << unavailable if unavailable > 0
      io << ", skipped " << skipped if skipped > 0
      io << ", failed " << failed if failed > 0
      io << ", waited on rate limits " << waits << " times" if waits > 0
      if message = error
        io << " -- " << message
      end
    end
  end
end
