require "./base_crawler"
require "./github_crawler"
require "./gitlab_crawler"
require "./codeberg_crawler"
require "./bitbucket_crawler"

module Discovery
  # Runs one host's sweep against the crawl_states row that remembers it.
  #
  # The runner owns three things the crawlers deliberately do not: which hosts
  # exist, refusing to start without the host's token, and writing the cursor and
  # the outcome down. A crawler can be driven without a database, which is what
  # makes it testable; this is what makes it durable.
  module CrawlRunner
    # The hosts a sweep enumerates. Named and reasoned about here rather than
    # left implicit, because "the indexer finds all shards on all git hosts" is
    # the claim this module either supports or quietly overstates.
    HOSTS = ["github.com", "gitlab.com", "codeberg.org", "bitbucket.org"]

    # Hosts and protocols that are NOT crawled, with why. A shard on one of these
    # still reaches the registry, by being submitted or pushed through a webhook;
    # what it does not do is get found on its own.
    #
    # What is left here are not hosts. Generic git, Mercurial and Fossil are
    # protocols. There is no global index of every git repository in the world,
    # so there is nothing to enumerate and no crawler that could exist. Saying
    # "we do not crawl Fossil" is not an admission of a gap.
    #
    # Bitbucket used to be listed here as one. It is crawled now, though not
    # globally, because globally is not on offer: see WORKSPACE_SCOPED.
    SUBMISSION_ONLY = {
      "generic git" => "a protocol, not a host: there is no index of all git repositories to enumerate",
      "mercurial"   => "a protocol, not a host: nothing global to enumerate",
      "fossil"      => "a protocol, not a host: nothing global to enumerate",
    }

    # Hosts that are crawled, but where the crawl cannot see the whole host and
    # no crawl could. Separate from SUBMISSION_ONLY because "we look, in the
    # places we were told to look" and "we do not look" are different promises,
    # and separate from a plain entry in HOSTS because reading this host's row
    # as a complete view of Bitbucket would be wrong.
    WORKSPACE_SCOPED = {
      "bitbucket.org" => "crawled workspace by workspace, because it has no global enumeration: " \
                         "GET /2.0/repositories answers 410 Gone (CHANGE-2770, functionality deprecated), " \
                         "GET /2.0/workspaces answers 401 and lists only workspaces the token already belongs to, " \
                         "and code search is reachable only under a workspace you have already named. " \
                         "Coverage is the set of registered workspaces, so a shard in an unregistered " \
                         "workspace is not merely unsearched, it is unreachable",
    }

    # One paragraph an operator can read to know what the registry's coverage
    # actually is. Printed by the backfill task so the boundary travels with the
    # numbers rather than living only in a commit message.
    def self.coverage_summary : String
      exhaustive = HOSTS.reject { |host| WORKSPACE_SCOPED.has_key?(host) }

      lines = ["Crawled hosts: #{exhaustive.join(", ")}."]

      unless WORKSPACE_SCOPED.empty?
        # Spelled out rather than folded into the list above, because a reader
        # who sees bitbucket.org among "crawled hosts" and stops there has been
        # told something false about what the registry knows.
        lines << "Crawled but never complete:"
        WORKSPACE_SCOPED.each do |name, reason|
          lines << "  #{name}: #{reason}."
          lines << "    Registered workspaces: #{workspace_coverage_note(name)}"
        end
      end

      lines << "Submission only:"
      SUBMISSION_ONLY.each { |name, reason| lines << "  #{name}: #{reason}" }
      lines.join("\n")
    end

    # How many places the workspace-scoped host is actually looking. A reason
    # without a number lets "crawled workspace by workspace" read as coverage
    # when the registration list is empty and the sweep looks nowhere at all.
    private def self.workspace_coverage_note(host : String) : String
      return "not applicable" unless host == "bitbucket.org"

      count = BitbucketWorkspaceQuery.new.enabled(true).select_count
      return "none registered, so nothing on this host is discovered automatically" if count.zero?

      "#{count} enabled. Anything outside them reaches the registry only by being submitted"
    rescue
      # Coverage is printed by a task that may run before the table exists.
      "unavailable"
    end

    def self.crawler_for(
      host : String,
      base_url : String? = nil,
      token : String? = nil,
      sleeper : Proc(Time::Span, Nil)? = nil,
      max_pages : Int32? = nil,
    ) : BaseCrawler
      case host
      when "github.com"
        GithubCrawler.new(base_url: base_url, token: token, sleeper: sleeper, max_pages: max_pages)
      when "gitlab.com"
        GitlabCrawler.new(base_url: base_url, token: token, sleeper: sleeper, max_pages: max_pages)
      when "codeberg.org"
        CodebergCrawler.new(base_url: base_url, token: token, sleeper: sleeper, max_pages: max_pages)
      when "bitbucket.org"
        BitbucketCrawler.new(
          workspaces: registered_workspaces,
          base_url: base_url,
          token: token,
          sleeper: sleeper,
          max_pages: max_pages,
        )
      else
        raise MissingTokenError.new("#{host} is not a host this registry knows how to crawl")
      end
    end

    # Sweeps one host and records what happened.
    #
    # `fresh` discards the stored cursor and starts the host over; without it the
    # sweep resumes from wherever the last run stopped, which is the behaviour
    # that lets a rate-limited or interrupted crawl eventually finish.
    def self.run(
      host : String,
      fresh : Bool = false,
      base_url : String? = nil,
      token : String? = nil,
      sleeper : Proc(Time::Span, Nil)? = nil,
      max_pages : Int32? = nil,
    ) : CrawlReport
      unless HOSTS.includes?(host)
        report = CrawlReport.new(host)
        report.status = CrawlState::Status::FAILED
        report.stop_reason = CrawlState::StopReason::UNSUPPORTED_HOST
        report.error = "#{host} is not a host this registry knows how to crawl"
        record(report, cursor: nil)
        return report
      end

      # Fail closed before anything is requested. A sweep that starts without the
      # token produces a handful of rows and a partial state, which reads like a
      # host with no shards on it rather than like missing configuration.
      unless token || Credentials.configured?(host)
        report = CrawlReport.new(host)
        report.status = CrawlState::Status::FAILED
        report.stop_reason = CrawlState::StopReason::TOKEN_MISSING
        report.error = Credentials.missing_message(host)
        Log.error { report.error }
        record(report, cursor: existing_cursor(host))
        return report
      end

      state = begin_crawl(host, fresh)
      cursor = fresh ? nil : state.cursor

      crawler = crawler_for(host, base_url: base_url, token: token, sleeper: sleeper, max_pages: max_pages)

      # Persisting after every page is what makes an interrupted sweep resumable
      # rather than restartable. A crawl that only saved at the end would, on a
      # rate-limited host, do the first pages over and over and never reach the
      # last one.
      crawler.on_page = ->(page_cursor : String?) do
        persist_cursor(host, page_cursor)
        nil
      end

      # Which registered workspaces answered, and which did not, recorded where
      # an operator manages them rather than only in the host's single error
      # column, where the second failing workspace overwrites the first.
      if bitbucket = crawler.as?(BitbucketCrawler)
        bitbucket.on_workspace_problem = ->(slug : String, reason : String) do
          note_workspace_problem(slug, reason)
        end
        bitbucket.on_workspace_seen = ->(slug : String, count : Int32) do
          note_workspace_seen(slug, count)
        end
      end

      report = crawler.run(cursor)
      record(report, cursor: report.cursor)
      Log.info { "Discovery #{report}" }
      report
    end

    def self.run_all(fresh : Bool = false, max_pages : Int32? = nil) : Array(CrawlReport)
      HOSTS.map { |host| run(host, fresh: fresh, max_pages: max_pages) }
    end

    def self.state_for(host : String) : CrawlState?
      CrawlStateQuery.new.for_host(host)
    end

    # The workspaces a Bitbucket sweep will walk. Read here rather than inside
    # the crawler so the crawler stays drivable without a database, which is
    # what lets its pagination and backoff be tested over a real socket.
    def self.registered_workspaces : Array(String)
      BitbucketWorkspaceQuery.new.enumerable.map(&.slug)
    end

    private def self.note_workspace_problem(slug : String, reason : String)
      workspace = BitbucketWorkspaceQuery.new.for_slug(slug)
      return unless workspace

      operation = SaveBitbucketWorkspace.new(workspace)
      operation.last_error.value = reason
      operation.update!
    end

    private def self.note_workspace_seen(slug : String, count : Int32)
      workspace = BitbucketWorkspaceQuery.new.for_slug(slug)
      return unless workspace

      operation = SaveBitbucketWorkspace.new(workspace)
      operation.last_seen_at.value = Time.utc
      operation.repository_count.value = count
      operation.last_error.value = nil
      operation.update!
    end

    private def self.existing_cursor(host : String) : String?
      state_for(host).try(&.cursor)
    end

    private def self.begin_crawl(host : String, fresh : Bool) : CrawlState
      state = state_for(host)

      return create_running(host) unless state

      # Counts describe one pass over a host. A resumed sweep is the same pass
      # continuing, so its counts keep adding up; a pass that starts from the
      # beginning starts them from zero, or a host would report a discovered
      # count that only ever grew.
      starting_over = fresh || state.cursor.nil?

      operation = SaveCrawlState.new(state)
      operation.status.value = CrawlState::Status::RUNNING
      operation.last_started_at.value = Time.utc
      operation.stop_reason.value = nil
      operation.last_error.value = nil

      if starting_over
        operation.cursor.value = nil
        operation.discovered_count.value = 0_i64
        operation.updated_count.value = 0_i64
        operation.unavailable_count.value = 0_i64
        operation.skipped_count.value = 0_i64
        operation.failed_count.value = 0_i64
      end

      operation.update!
    end

    private def self.create_running(host : String) : CrawlState
      SaveCrawlState.create!(
        host: host,
        status: CrawlState::Status::RUNNING,
        last_started_at: Time.utc,
      )
    end

    private def self.persist_cursor(host : String, cursor : String?)
      state = state_for(host)
      return unless state

      operation = SaveCrawlState.new(state)
      operation.cursor.value = cursor
      operation.update!
    end

    private def self.record(report : CrawlReport, cursor : String?)
      state = state_for(report.host)
      completed_at = report.complete? ? (report.finished_at || Time.utc) : state.try(&.last_completed_at)

      unless state
        SaveCrawlState.create!(
          host: report.host,
          status: report.status,
          cursor: cursor,
          stop_reason: report.stop_reason,
          last_error: report.error,
          last_started_at: report.started_at,
          last_completed_at: completed_at,
          discovered_count: report.discovered.to_i64,
          updated_count: report.updated.to_i64,
          unavailable_count: report.unavailable.to_i64,
          skipped_count: report.skipped.to_i64,
          failed_count: report.failed.to_i64,
        )
        return
      end

      operation = SaveCrawlState.new(state)
      operation.status.value = report.status
      operation.cursor.value = cursor
      operation.stop_reason.value = report.stop_reason
      operation.last_error.value = report.error
      operation.last_completed_at.value = completed_at
      operation.discovered_count.value = state.discovered_count + report.discovered
      operation.updated_count.value = state.updated_count + report.updated
      operation.unavailable_count.value = state.unavailable_count + report.unavailable
      operation.skipped_count.value = state.skipped_count + report.skipped
      operation.failed_count.value = state.failed_count + report.failed
      operation.update!
    end
  end
end
