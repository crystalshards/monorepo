require "yaml"
require "./credentials"
require "./host_client"
require "./discovered_repository"
require "./registrar"

module Discovery
  # The part of a crawl that is the same on every host.
  #
  # A subclass answers three host-specific questions: how to ask for a page of
  # candidate repositories, how to ask whether one has a shard.yml at its root,
  # and whether its enumeration can see every shard on the host. Everything that
  # makes a crawl trustworthy lives here, once:
  #
  #   - pages are followed until the host says there are none left, never to a
  #     fixed page count
  #   - the cursor is persisted after every page, so an interrupted sweep resumes
  #     from where it stopped instead of starting over
  #   - a rate limit stops the sweep and records it as partial with the cursor
  #     intact, rather than dropping the remaining pages and reporting success
  #   - a repository already in the registry is updated, never duplicated
  #   - a repository that has lost its shard.yml is marked unavailable
  abstract class BaseCrawler
    # How many pages a single run will take before stopping with its cursor
    # saved. Bounds one job's runtime without bounding the crawl: the next run
    # resumes from the cursor. Nil means "until the host runs out of pages".
    property max_pages : Int32? = nil

    getter host : String
    getter report : CrawlReport
    getter client : HostClient

    def initialize(
      @host : String,
      base_url : String? = nil,
      token : String? = nil,
      sleeper : Proc(Time::Span, Nil)? = nil,
      @max_pages : Int32? = nil,
    )
      resolved_token = token || Credentials.token_for(@host)
      @report = CrawlReport.new(@host)
      @client = build_client(base_url || default_base_url, resolved_token, sleeper)
    end

    # The API root. Specs point this at a local server; nothing else overrides it.
    abstract def default_base_url : String

    # One page of candidates, and the cursor to resume from. Returning a page
    # whose next_cursor is nil declares the enumeration finished.
    abstract def fetch_page(cursor : String?) : CrawlPage

    # The shard.yml at the repository's root, or nil when there is none. nil is
    # the signal that the repository is not a shard, so it must mean exactly
    # that: a transport failure has to raise, not return nil, or a rate-limited
    # sweep would mark every repository it could not read as "not a shard".
    abstract def fetch_shard_yml(repository : DiscoveredRepository) : String?

    # Whether this host's enumeration can see every shard on it. False means a
    # finished sweep is still recorded as partial, because "we looked at
    # everything we can ask for" is not the same as "we looked at everything".
    abstract def exhaustive? : Bool

    # Called after every page with the cursor to resume from. The runner points
    # this at the crawl_states row; it defaults to a no-op so a crawler can be
    # driven without a database.
    property on_page : Proc(String?, Nil) = ->(_cursor : String?) { }

    def run(cursor : String? = nil) : CrawlReport
      report.cursor = cursor
      pages_this_run = 0

      loop do
        page = fetch_page(cursor)
        report.pages += 1
        pages_this_run += 1

        page.repositories.each { |repository| process(repository) }

        cursor = page.next_cursor
        report.cursor = cursor
        on_page.call(cursor)

        if cursor.nil?
          finish_completed
          break
        end

        if (limit = max_pages) && pages_this_run >= limit
          # Not a failure and not a success: the sweep has more to do and knows
          # exactly where to pick it up.
          report.status = CrawlState::Status::PARTIAL
          report.stop_reason = CrawlState::StopReason::INTERRUPTED
          break
        end
      end

      finish_report
    rescue ex : HostClient::RateLimited
      # The cursor already points at the page that was not read, so the next run
      # starts there. Recording this as anything other than partial would tell
      # the registry it has a complete view of the host.
      report.status = CrawlState::Status::PARTIAL
      report.stop_reason = CrawlState::StopReason::RATE_LIMITED
      report.error = ex.message
      Log.warn { "#{host} crawl paused by rate limit, resuming from cursor #{report.cursor.inspect}: #{ex.message}" }
      finish_report
    rescue ex : HostClient::Error
      report.status = CrawlState::Status::FAILED
      report.stop_reason = CrawlState::StopReason::ERROR
      report.error = ex.message
      Log.error { "#{host} crawl failed: #{ex.message}" }
      finish_report
    end

    # Why a finished sweep still is not a complete view of the host. Only
    # consulted when `exhaustive?` is false, and overridden by a crawler whose
    # coverage can fall short for more than one reason.
    def coverage_reason : String
      CrawlState::StopReason::COMPLETED_TOPIC_SCOPED
    end

    private def finish_completed
      if exhaustive?
        report.status = CrawlState::Status::COMPLETED
        report.stop_reason = CrawlState::StopReason::COMPLETED_EXHAUSTIVE
      else
        # Finished, but not over everything. Recorded as partial so nothing
        # downstream reads "the sweep ended" as "the host has been seen".
        report.status = CrawlState::Status::PARTIAL
        report.stop_reason = coverage_reason
      end
    end

    private def finish_report : CrawlReport
      report.finished_at = Time.utc
      report.requests = client.requests_made
      report.waits = client.waits.size
      report
    end

    private def process(repository : DiscoveredRepository)
      contents = begin
        fetch_shard_yml(repository)
      rescue ex : HostClient::NotFound
        nil
      end

      unless contents
        # Not a shard. If we had it registered, it either lost its shard.yml or
        # stopped being reachable, and either way the registry should stop
        # showing it as live.
        if Registrar.known?(repository)
          if Registrar.mark_unavailable(repository, "shard.yml no longer present at the root of #{repository.slug}")
            report.unavailable += 1
            return
          end
        end

        report.skipped += 1
        return
      end

      shard_yml = parse_shard_yml(contents)
      unless shard_yml
        report.skipped += 1
        Log.info { "#{repository.slug} has a shard.yml that does not parse, skipping" }
        return
      end

      name = shard_name(shard_yml) || repository.repo
      description = yaml_string(shard_yml, "description") || repository.description

      result = Registrar.register(repository, name, description)

      case result.outcome
      in Registrar::Outcome::Created
        report.discovered += 1
      in Registrar::Outcome::Updated
        report.updated += 1
      in Registrar::Outcome::Skipped
        report.skipped += 1
        Log.info { "Skipped #{result.detail}" }
      in Registrar::Outcome::Failed
        report.failed += 1
        Log.error { "Failed to register #{result.detail}" }
      end
    end

    private def parse_shard_yml(contents : String) : YAML::Any?
      parsed = YAML.parse(contents)
      # A YAML document can legally be a string or a list; a shard.yml is a
      # mapping with a name in it. Anything else is not a shard.yml.
      return nil unless parsed.as_h?
      parsed
    rescue YAML::ParseException
      nil
    end

    private def shard_name(shard_yml : YAML::Any) : String?
      name = yaml_string(shard_yml, "name")
      return nil unless name

      trimmed = name.strip
      trimmed.empty? ? nil : trimmed
    end

    private def yaml_string(shard_yml : YAML::Any, key : String) : String?
      value = shard_yml[key]?
      return nil unless value

      value.as_s?.try(&.strip).presence
    end

    private def build_client(base_url : String, token : String?, sleeper : Proc(Time::Span, Nil)?) : HostClient
      gate = url_gate_for(base_url)

      if sleeper
        HostClient.new(host: host, base_url: base_url, headers: auth_headers(token), sleeper: sleeper, url_gate: gate)
      else
        HostClient.new(host: host, base_url: base_url, headers: auth_headers(token), url_gate: gate)
      end
    end

    # A check every request's absolute URL passes before it is sent, or nil for
    # a host that only ever builds its own relative paths and so has nothing a
    # response body could redirect.
    #
    # Takes the base URL rather than reading one off the instance, because this
    # is called while the base class is still constructing and a subclass's own
    # fields are not set yet.
    def url_gate_for(base_url : String) : Proc(String, Nil)?
      nil
    end

    # How this host wants its token presented.
    abstract def auth_headers(token : String?) : HTTP::Headers
  end
end
