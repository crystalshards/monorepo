require "./base_crawler"
require "./github_crawler"
require "./gitlab_crawler"
require "./codeberg_crawler"

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
    HOSTS = ["github.com", "gitlab.com", "codeberg.org"]

    # Hosts and protocols that are NOT crawled, with why. A shard on one of these
    # still reaches the registry, by being submitted or pushed through a webhook;
    # what it does not do is get found on its own.
    #
    # The distinction that matters: the first entry is a host with an API we have
    # not built a crawler for, and the rest are not hosts at all. Generic git,
    # Mercurial and Fossil are protocols. There is no global index of every git
    # repository in the world, so there is nothing to enumerate and no crawler
    # that could exist. Saying "we do not crawl Fossil" is not an admission of a
    # gap; saying "we do not crawl Bitbucket" is.
    SUBMISSION_ONLY = {
      "bitbucket.org" => "has a public repositories API and could be crawled, but no crawler is built yet",
      "generic git"   => "a protocol, not a host: there is no index of all git repositories to enumerate",
      "mercurial"     => "a protocol, not a host: nothing global to enumerate",
      "fossil"        => "a protocol, not a host: nothing global to enumerate",
    }

    # One paragraph an operator can read to know what the registry's coverage
    # actually is. Printed by the backfill task so the boundary travels with the
    # numbers rather than living only in a commit message.
    def self.coverage_summary : String
      lines = ["Crawled hosts: #{HOSTS.join(", ")}."]
      lines << "Submission only:"
      SUBMISSION_ONLY.each { |name, reason| lines << "  #{name}: #{reason}" }
      lines.join("\n")
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
