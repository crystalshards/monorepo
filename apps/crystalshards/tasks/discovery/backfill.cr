require "../../src/services/discovery/crawl_runner"

# Runs a discovery sweep on demand, in the foreground, printing what happened.
#
#   lucky discovery.backfill                      every host, resuming each
#   lucky discovery.backfill --host=github.com    one host
#   lucky discovery.backfill --fresh              start over, ignoring cursors
#   lucky discovery.backfill --max-pages=2        stop after two pages per host
#
# The sweep is the same code the worker runs, so what this prints is what the
# queue would do. `--max-pages` exists for exactly that: a bounded run against a
# real host that leaves a resumable cursor behind.
class Discovery::Backfill < LuckyTask::Task
  summary "Sweep git hosts for shards and record what was found"

  arg :host, "Host to sweep (github.com, gitlab.com, codeberg.org). Defaults to all of them.", optional: true
  arg :max_pages, "Stop after this many pages per host, leaving a resumable cursor", optional: true
  switch :fresh, "Discard the saved cursor and sweep the host from the beginning"

  def call
    hosts = resolve_hosts
    return if hosts.empty?

    limit = parse_max_pages
    return if limit == :invalid

    reports = hosts.map do |target|
      puts "Sweeping #{target}#{fresh? ? " from the beginning" : resume_note(target)}"
      Discovery::CrawlRunner.run(target, fresh: fresh?, max_pages: limit.as(Int32?))
    end

    print_results(reports)
  end

  private def resolve_hosts : Array(String)
    requested = host
    return Discovery::CrawlRunner::HOSTS unless requested

    unless Discovery::CrawlRunner::HOSTS.includes?(requested)
      puts "#{requested} is not a host this registry crawls."
      puts "Known hosts: #{Discovery::CrawlRunner::HOSTS.join(", ")}"
      return [] of String
    end

    [requested]
  end

  private def parse_max_pages
    raw = max_pages
    return nil unless raw

    value = raw.to_i?
    if value.nil? || value < 1
      puts "--max-pages must be a positive whole number, got #{raw.inspect}"
      return :invalid
    end

    value
  end

  private def resume_note(target : String) : String
    state = Discovery::CrawlRunner.state_for(target)
    return "" unless state && state.resumable?

    " resuming from the saved cursor"
  end

  private def print_results(reports : Array(Discovery::CrawlReport))
    puts ""
    puts "Results"

    reports.each do |report|
      puts "  #{report}"
    end

    puts ""

    incomplete = reports.reject(&.complete?)

    if incomplete.empty?
      puts "Every host swept completely."
    else
      # The distinction the registry has to keep straight: a host that finished
      # and a host that has not been fully seen are not the same, even when both
      # look like a successful command.
      puts "Not a complete view of these hosts yet:"
      incomplete.each do |report|
        puts "  #{report.host}: #{report.status} (#{report.stop_reason})"
        case report.stop_reason
        when CrawlState::StopReason::TOKEN_MISSING
          puts "    #{report.error}"
        when CrawlState::StopReason::RATE_LIMITED, CrawlState::StopReason::INTERRUPTED
          puts "    Run this again to continue from the saved cursor."
        when CrawlState::StopReason::COMPLETED_TOPIC_SCOPED
          puts "    This host is enumerated by topic, so shards without the topic are not discovered here."
        when CrawlState::StopReason::RESULT_CAP_TRUNCATED
          puts "    A search window held more results than the host will return and could not be"
          puts "    narrowed further, so some shards in it are unreachable by any query we can write."
        when CrawlState::StopReason::UNSUPPORTED_HOST
          puts "    #{report.error}"
        end
      end
    end

    # Coverage is part of the result, not a footnote. Discovery covers three
    # hosts; anything else reaches the registry only by being submitted, and an
    # operator reading this output should not have to infer that.
    puts ""
    puts Discovery::CrawlRunner.coverage_summary
  end
end
