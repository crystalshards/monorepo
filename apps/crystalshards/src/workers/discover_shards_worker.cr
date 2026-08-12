require "./base_worker"
require "../services/discovery/crawl_runner"

# Sweeps one git host for shards.
#
# One job is one host, and it is safe to run repeatedly: the sweep resumes from
# the cursor in crawl_states, so a run that was rate limited or bounded by
# max_pages continues where it stopped instead of starting the host over. That is
# what makes a host with more shards than one job's worth of pages reachable at
# all.
#
# This is NOT what runs on a schedule. The scheduled sweep is the discover-shards
# Cloud Run Job, which runs the ./discover-shards binary built from
# src/discover_shards.cr and drives every configured host through
# `Discovery::Sweep`. Nothing enqueues this job today.
#
# It is kept because its contract is genuinely different from the Job's, in the
# one place that matters: a refused sweep is not a failed job here, because a
# queue would retry a missing token until it gave up, while the Job must exit
# non-zero so an operator finds out. Anything that wants one host swept through
# the normal dispatch path wants this; a schedule wants the Job.
struct DiscoverShardsWorker < BaseJob
  # Test seam. The sweep is performed through this proc, which defaults to the
  # real runner. Specs replace it to observe the job without touching a host, and
  # must restore it in an `ensure`.
  class_property runner : Proc(String, Bool, Int32?, Discovery::CrawlReport) = ->(host : String, fresh : Bool, max_pages : Int32?) {
    Discovery::CrawlRunner.run(host, fresh: fresh, max_pages: max_pages)
  }

  # `max_pages` bounds a single job, not the crawl. Nil means run until the host
  # says there are no pages left.
  def initialize(@host : String, @fresh : Bool = false, @max_pages : Int32? = nil)
    @queue = "discovery"
  end

  def perform
    log_info "Discovering shards on #{@host}#{@fresh ? " (starting over)" : ""}"

    report = @@runner.call(@host, @fresh, @max_pages)

    if report.failed?
      # A failed sweep is not a failed job: the reason is recorded on the host's
      # crawl_states row, and raising here would only retry a missing token or an
      # unsupported host until the queue gave up.
      log_error "Discovery on #{@host} did not run: #{report.error}"
      return
    end

    log_info "Discovery on #{@host}: #{report}"

    if report.partial?
      log_info "#{@host} is not fully swept yet; the next run resumes from the saved cursor"
    end
  rescue ex : Exception
    log_error "Discovery on #{@host} raised", ex
    raise ex
  end
end
