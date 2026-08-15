class CreateSearchProbes::V00000000000020 < Avram::Migrator::Migration::V1
  def migrate
    # One search term this registry has taken to GitHub, and when.
    #
    # The table exists to answer one question before a page load spends a
    # request: has anybody already asked GitHub about this term recently. Every
    # other property of the probe follows from getting that answer right.
    #
    # Without it the feature is a denial of service against our own credential.
    # GitHub's code search allows 10 requests a minute, one search term is one
    # request, and the trigger is a visitor typing into a box. A crawler walking
    # a paginated listing, or one impatient reload, exhausts the minute's budget
    # and takes the exhaustive sweep's bucket down with it, because they draw on
    # the same code_search pool. A term probed once is a term that costs nothing
    # to search for again.
    #
    # It is also the record of what the probe learned. `hits` and `registered`
    # differ whenever GitHub matched repositories the registry already had,
    # which is the normal case for a common word and the number that says
    # whether widening the trigger would be worth anything.
    create table_for(SearchProbe) do
      primary_key id : Int64
      add_timestamps

      # Normalised, and unique on that normalisation. "Kemal", "kemal " and
      # "kemal" are one question about one ecosystem, and letting them be three
      # rows would let three page loads each spend a request to learn the same
      # thing.
      add term : String, unique: true

      # Stamped before the search runs, not after, so a probe whose process died
      # mid-flight still holds the claim and is retried on the ordinary schedule
      # rather than immediately by the next visitor. Same ordering, and the same
      # reasoning, as ShardIndexer's claim.
      add probed_at : Time

      # What the last probe found. Nilable because a probe that failed learned
      # nothing, and zero would claim it had looked and found nothing.
      add hits : Int32?
      add registered : Int32?
      add last_error : String?
    end

    # The eligibility query is "this term, is it stale", which the unique index
    # on term already serves. No second index: probed_at is read only for a row
    # already located by term.
  end

  def rollback
    drop table_for(SearchProbe)
  end
end
