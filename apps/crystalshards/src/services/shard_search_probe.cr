require "./discovery/keyword_crawler"
require "./discovery/credentials"

# Takes a search the registry could not answer to GitHub, once, while the
# visitor waits.
#
# WHY.
#
# The scheduled sweep finished. github.com reported completed_exhaustive, which
# means the registry holds everything GitHub's code search index will admit for
# a root shard.yml, and the three other hosts have no credential. So a search
# that returns nothing here is not usually a search that was too early: it is a
# search for something outside what one enumeration could ever see. The visitor
# has just told us exactly what they were looking for, which is a better query
# than any partition of file sizes, and it costs one request to ask it.
#
# This is the same move ShardIndexRequests makes one level down. That indexes a
# shard the moment a reader visits it rather than leaving it for the sweep; this
# finds one the moment a reader looks for it. Both run inline, both are bounded,
# both fail into the honest state rather than into an error.
#
# WHAT IT DOES NOT DO.
#
# It does not index what it finds. Registering gives a result card its name,
# description and link, which is what a search result needs; content costs three
# more core requests per repository and nobody has asked for any of them yet.
# The reader who clicks through gets ShardIndexRequests, which indexes that one
# shard on the spot. Fetching all ten in the search request would spend thirty
# requests, and most of a reader's patience, on nine pages they did not open.
#
# WHY THE CLAIM IS THE HARD PART.
#
# GitHub's code search allows ten requests a minute, on a bucket shared with the
# exhaustive sweep, and the trigger for a probe is a text box. One crawler
# walking a paginated listing, or a reader reloading, would exhaust that minute
# and take the sweep down with it. So a term is probed at most once per window,
# the claim is a conditional UPDATE that only one caller can win, and everything
# else about this module is subordinate to that.
module ShardSearchProbe
  # How stale a term's last probe must be before another visitor may spend a
  # request on it again.
  #
  # Long, deliberately. What a probe learns is "which repositories on GitHub
  # have a shard.yml at their root and match this word", and that answer moves
  # on the timescale of somebody publishing a shard, not of somebody reloading.
  # A day means a term costs at most one code_search request a day however
  # popular it is, which is what keeps a shared ten-a-minute bucket usable.
  RETRY_FLOOR = 24.hours

  # Terms shorter than this are not probed.
  #
  # A one or two character query matches an enormous amount of GitHub and
  # almost nothing usefully, so the request buys nothing and the claim row is
  # wasted on a term nobody meant.
  MIN_TERM_LENGTH = 3

  # Probe only when the registry has fewer local results than this.
  #
  # The feature is for the search the registry answered badly, and the number
  # was measured rather than chosen. It started at 3, on the reasoning that only
  # an empty page was worth a request, and that turned out to gate out precisely
  # the searches with something to find. Sampled against production and against
  # GitHub's code search: "webview" had 5 local results and one matching
  # repository the registry did not hold, and "prometheus" had 9 local results
  # and one. Both were refused by a threshold of 3. Every term thin enough to
  # pass it, meanwhile, was a term the exhaustive crawl had already covered
  # completely, so the probe reliably spent a request to learn nothing.
  #
  # The gap is not in the empty searches. It is in the ones returning a handful,
  # which is what a partially covered topic looks like. 10 is half a listing
  # page: below it a reader cannot fill their screen, which is the honest line
  # between "answered" and "answered badly".
  THIN_RESULTS = 10

  # Probes allowed across the whole site in any one minute.
  #
  # This is the guard the per-term claim cannot provide, and shipping without it
  # was a hole in the protection this module claims to give. RETRY_FLOOR stops
  # one term being asked twice; it does nothing about a hundred DIFFERENT terms,
  # which is what a crawler walking a search-results listing produces, and what
  # a busy hour produces on its own.
  #
  # GitHub's code search allows ten requests a minute and the exhaustive sweep
  # draws on the same bucket. Measured the hard way while verifying this
  # feature: a handful of sequential code searches from one terminal returned
  # 403 for everything after them. A per-term limit would not have stopped any
  # of it.
  #
  # Five leaves half the bucket for the sweep, which needs about ten requests
  # per scheduled run and must never be starved by page traffic. A search over
  # the budget is not an error and not a delay: it renders from the database, as
  # it would have if nobody had built this.
  PROBES_PER_MINUTE = 5

  # How long a probe may take before the page gives up waiting on it.
  #
  # One code_search request plus up to KeywordCrawler::PER_PAGE reads of a
  # shard.yml, so eleven sequential calls to GitHub. Ten seconds is generous for
  # that and well inside what a reader, and a load balancer, will tolerate. A
  # probe that overruns is not cancelled, because Crystal cannot interrupt a
  # fiber: it keeps running and its writes still land, the page simply renders
  # without waiting. The claim is already stamped, so nothing runs it twice.
  #
  # A class_property, not a constant, so a spec can shrink it to prove the
  # timeout path renders without a real ten second wait.
  class_property inline_timeout : Time::Span = 10.seconds

  # Test seam. Every probe builds its crawler here, so specs drive the whole
  # module against a recorded transport with nothing on a socket, and must
  # restore it in an `ensure`.
  class_property crawler : Proc(String, Discovery::KeywordCrawler) = ->(term : String) {
    Discovery::KeywordCrawler.new(term)
  }

  # Whether this deployment can probe at all.
  #
  # Fail closed, and silently: code search answers an unauthenticated request
  # with 401, so a deployment with no token cannot do this and there is nothing
  # a visitor could do about it. Same arrangement the crawlers have, and the
  # same one mail has in this repo: the feature is off and the process is fine.
  def self.enabled? : Bool
    Discovery::Credentials.configured?(Discovery::KeywordCrawler::HOST)
  end

  # Runs a probe for `term` when one is worth running, and answers how many
  # repositories it registered.
  #
  # nil means no probe happened, for any of the ordinary reasons: the feature is
  # off, the term is too short, the registry answered the search well enough,
  # somebody asked this recently, or the site has spent its minute's budget. The
  # caller renders what it already had, which is what it would have rendered if
  # none of this existed.
  def self.request(term : String?, local_results : Int64) : Int32?
    return nil unless enabled?
    return nil if local_results >= THIN_RESULTS

    normalized = normalized_term(term)
    return nil unless normalized

    # Checked before the claim, not after, and the order is the point. A claim
    # stamps `probed_at`, which suppresses the term for RETRY_FLOOR. Taking one
    # and then refusing to spend the request would silence that term for a day
    # over a busy minute it had nothing to do with.
    return nil unless within_budget?
    return nil unless claimed?(normalized)

    run_bounded(normalized)
  rescue ex : Exception
    # Whatever failed here, the search must not. An empty result page is a worse
    # answer than a full one and a much better one than a 500.
    Log.error(exception: ex) { "Search probe for #{term.inspect} failed" }
    nil
  end

  # Whether the site has a probe left in this minute.
  #
  # Counted from the claims themselves rather than from a counter, so it needs no
  # state of its own and cannot drift from what actually happened. A rolling
  # window rather than a fixed one: fixed windows let twice the budget through
  # across a boundary, which against a ten-a-minute bucket is the whole budget.
  def self.within_budget? : Bool
    spent = AppDatabase.query_one(
      "SELECT COUNT(*) FROM search_probes WHERE probed_at > $1",
      Time.utc - 1.minute,
      as: Int64
    )

    return true if spent < PROBES_PER_MINUTE

    Log.info do
      "Search probe declined: #{spent} probes in the last minute is the site's budget of " \
      "#{PROBES_PER_MINUTE}. Rendering from the registry instead."
    end
    false
  end

  private def self.normalized_term(term : String?) : String?
    return nil unless term

    normalized = SearchProbe.normalize(term)
    return nil if normalized.size < MIN_TERM_LENGTH

    # A term made entirely of punctuation normalises to something long enough
    # and searches for nothing. KeywordCrawler strips those characters before
    # they reach GitHub, so the query it would send is empty.
    return nil unless normalized.matches?(/[A-Za-z0-9]/)

    normalized
  end

  # The same race ShardIndexRequests and CrystalDocs::DocBuildRequests win the
  # same way. An unconditional read-then-write would let two visitors landing on
  # the same cold term both believe they had claimed it, and both spend a
  # request. Making "did I win" and "is the row now claimed" one statement with
  # one answer is what removes the window entirely.
  #
  # The insert and the update are one statement for the same reason: a term
  # nobody has ever searched and a term searched last week are the same question
  # to a caller, and answering them with two round trips would put the race back
  # between them.
  CLAIM_SQL = <<-SQL
    INSERT INTO search_probes (term, probed_at, created_at, updated_at)
    VALUES ($1, $2, $2, $2)
    ON CONFLICT (term) DO UPDATE
      SET probed_at = EXCLUDED.probed_at,
          updated_at = EXCLUDED.updated_at,
          last_error = NULL
      WHERE search_probes.probed_at <= $3
    RETURNING id
    SQL

  private def self.claimed?(term : String) : Bool
    now = Time.utc

    AppDatabase.query_all(
      CLAIM_SQL,
      term,
      now,
      now - RETRY_FLOOR,
      as: Int64
    ).any?
  end

  # Runs the probe with a bound, so a slow host cannot hold a page open.
  #
  # select over a Channel rather than a bare call, because Crystal cannot
  # interrupt a fiber: the one doing the search keeps running after this stops
  # waiting, finishes its registrations and records its outcome. That is the
  # right outcome rather than a leak. The work was worth doing, the claim is
  # already stamped so nothing repeats it, and the only thing lost is this
  # visitor seeing the results in this page load.
  private def self.run_bounded(term : String) : Int32?
    done = Channel(Int32?).new(1)

    spawn do
      begin
        done.send(probe(term))
      rescue ex : Exception
        Log.error(exception: ex) { "Search probe for #{term.inspect} raised" }
        record_failure(term, ex.message.presence || ex.class.name)
        done.send(nil)
      end
    end

    select
    when registered = done.receive
      registered
    when timeout(@@inline_timeout)
      Log.warn { "Search probe for #{term.inspect} exceeded #{@@inline_timeout}, rendering what we already had" }
      nil
    end
  end

  private def self.probe(term : String) : Int32?
    report = @@crawler.call(term).run(nil)

    record_outcome(term, report)

    Log.info do
      "Search probe #{term.inspect}: #{report.discovered} new, #{report.updated} already known, " \
      "#{report.requests} requests"
    end

    report.discovered
  end

  private def self.record_outcome(term : String, report : Discovery::CrawlReport) : Nil
    AppDatabase.exec(
      <<-SQL,
      UPDATE search_probes
      SET hits = $2, registered = $3, last_error = $4, updated_at = NOW()
      WHERE term = $1
      SQL
      term,
      report.discovered + report.updated,
      report.discovered,
      report.error,
    )
  end

  private def self.record_failure(term : String, message : String) : Nil
    AppDatabase.exec(
      "UPDATE search_probes SET last_error = $2, updated_at = NOW() WHERE term = $1",
      term,
      message,
    )
  end
end
