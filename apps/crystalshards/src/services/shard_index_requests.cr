require "./shard_indexer"

# Indexes one shard the moment a reader visits it, rather than leaving it to
# wait for IndexSweep's next scheduled pass.
#
# Run inline, in the reader's own request, the same way index_shard and
# update_dependencies already run for create/upload. job_queue.cr's own
# reasoning for "run it now" applies here without change: a handful of
# database writes plus a read from the shard's host, no code from the shard
# ever executes, and the work finishes inside the time an HTTP request
# already allows. A separate durable queue was considered and rejected: the
# receiver would need its own Cloud Run service, since Cloud Tasks cannot
# reach a service behind the load balancer the way it reaches docs-launcher,
# and that is far more machinery than commissioning a few host reads is
# worth. IndexSweep runs every six hours, so deferring to it is not "on
# demand" by any reading anyway.
#
# The claim reuses the three columns ShardIndexer and IndexSweep already
# stamp -- indexed_at, index_attempted_at, index_error -- rather than adding
# state of its own. A visit is not a different KIND of indexing than the
# sweep's, it is the same indexing commissioned early, so it belongs on the
# same row with the same meaning, and a shard the sweep has already reached
# is exactly as ineligible here as it is there.
module ShardIndexRequests
  # How long a claim is left alone before a later visit may retry it.
  #
  # Measured from index_attempted_at, which is stamped before the index runs
  # rather than after, so this also bounds how long a shard whose indexing
  # fiber never reported back (the container's CPU reclaimed mid-run, the
  # same risk ShardIndexer's own claim-first ordering already documents for
  # a killed sweep pass) is left looking claimed. Ten minutes is far beyond
  # what indexing itself needs (see inline_timeout) and short enough that a
  # reader who reloads within the hour gets a fresh attempt.
  RETRY_FLOOR = 10.minutes

  # How long a winning claim may spend running the index inline before this
  # gives up on waiting and renders the honest state instead.
  #
  # ShardIndexer makes a handful of sequential host calls: the repository and
  # its tag list, one commit to date the version being indexed, shard.yml,
  # and a README lookup that tries up to six candidate filenames in turn
  # before giving up. None of that is the minutes a documentation compile
  # takes. Twenty seconds is generous room for that worst case against a slow
  # host while staying well inside what a reader waiting on a page load, and
  # most load balancers' own upstream timeouts, will tolerate.
  #
  # A class_property, not a constant, so a spec can shrink it to prove the
  # timeout path renders the honest state without a real 20 second wait.
  class_property inline_timeout : Time::Span = 20.seconds

  # Test seam. Every on-demand index runs through this proc, which defaults
  # to the real call so production is unchanged when nothing installs a
  # fake. Specs swap it out to control the outcome (indexed, failed, or
  # slow enough to trip inline_timeout) without reaching a real host, and
  # must restore it in an `ensure`.
  class_property indexer : Proc(Shard, ShardIndexer::Result) = ->(shard : Shard) {
    ShardIndexer.index(shard)
  }

  # The same race CrystalDocs::DocBuildRequests wins the same way: an
  # unconditional UPDATE would let two readers landing on the same cold shard
  # both believe they had claimed it. Scoping the WHERE clause to eligibility
  # and reading back only the row RETURNING actually touched makes "did I
  # win" and "is the row now claimed" the same question with the same
  # answer, so a check-then-write in this process can never race itself.
  #
  # index_error is cleared unconditionally on a winning claim, matching
  # ShardIndexer's own claim: a new attempt is about to learn a fresh answer,
  # and the old failure would be stale and misleading the moment it starts.
  CLAIM_SQL = <<-SQL
    UPDATE shards
    SET index_attempted_at = $2,
        index_error = NULL,
        updated_at = NOW()
    WHERE id = $1
      AND indexed_at IS NULL
      AND (index_attempted_at IS NULL OR index_attempted_at <= $3)
    RETURNING id
    SQL

  # Claims and, on a win, indexes this shard before returning. Safe to call
  # on every page view: a shard already indexed, already claimed, or claimed
  # within the retry floor, claims nothing and does nothing, so however many
  # times or however many routes a reader (or a crawler) reaches the same
  # shard through, at most one indexing pass is ever running for it and a
  # request that loses the race does not wait on the one that won.
  #
  # Returns the freshly reloaded shard, with shard_versions preloaded to
  # match what every caller of render_show_page already loads, when this
  # call is the one that actually indexed it. Returns nil in every other
  # case -- already indexed, no identity to claim on, lost the claim, or the
  # attempt failed or timed out -- meaning the caller's own copy is still
  # the correct thing to render.
  def self.request(shard : Shard) : Shard?
    return nil if shard.indexed_at

    slug = shard.canonical_slug
    return nil unless slug

    now = Time.utc
    return nil unless claimed?(shard, now)
    return nil unless run_bounded(shard)

    ShardQuery.new.preload_shard_versions.canonical_slug(slug).first?
  rescue ex : Exception
    # Whatever failed here, the render must not: the same honest "found, not
    # read yet" state already covers a claim that never got attempted.
    Log.error(exception: ex) { "Could not index #{shard.canonical_slug || shard.name} on visit" }
    nil
  end

  # A shard with no canonical_slug has nothing to key the claim on and
  # nothing ShardIndexer could resolve a host from either: the page already
  # says why under "Not indexed", and a claim here would only spend an
  # attempt that fails before it fetches anything. Guarded by request's own
  # `return nil unless slug` before this is ever reached.
  private def self.claimed?(shard : Shard, now : Time) : Bool
    AppDatabase.query_all(
      CLAIM_SQL,
      shard.id.not_nil!,
      now,
      now - RETRY_FLOOR,
      as: Int64
    ).any?
  end

  # Runs the index with a bound, so a reader's page load cannot hang on a
  # host that never answers.
  #
  # select over a Channel rather than a bare call, because Crystal has no way
  # to interrupt a fiber mid-flight: the fiber doing the fetch keeps running
  # even after this gives up on waiting for it. That is not a new risk this
  # introduces -- it is exactly the "process killed mid-shard" case
  # ShardIndexer's own claim-first design already documents, and the row is
  # left in the identical shape: index_attempted_at set, indexed_at and
  # index_error untouched, which IndexSweep already recovers on a later pass
  # once the retry floor passes.
  private def self.run_bounded(shard : Shard) : Bool
    done = Channel(Bool).new(1)

    spawn do
      begin
        result = @@indexer.call(shard)
        done.send(result.indexed?)
      rescue ex : Exception
        # Mirrors IndexSweep.run's own per-shard rescue: one shard raising
        # here must not look like a crash rather than an indexing failure.
        Log.error(exception: ex) { "On-demand indexing of #{shard.canonical_slug} raised" }
        done.send(false)
      end
    end

    select
    when indexed = done.receive
      indexed
    when timeout(@@inline_timeout)
      Log.warn { "On-demand indexing of #{shard.canonical_slug} exceeded #{@@inline_timeout}, rendering the honest state instead" }
      false
    end
  end
end
