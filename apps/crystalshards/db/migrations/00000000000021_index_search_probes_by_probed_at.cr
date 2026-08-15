class IndexSearchProbesByProbedAt::V00000000000021 < Avram::Migrator::Migration::V1
  def migrate
    # The global rate guard counts probes in the last minute, on every search
    # thin enough to be a candidate. The unique index on `term` cannot serve
    # that: it answers "this term", and this question has no term in it.
    #
    # Deliberately added rather than left to a sequential scan. The count runs
    # before a claim is taken, which means it runs on searches that then do
    # nothing, and search_probes grows by one row per distinct term the site has
    # ever been asked about. A scan is fine at a hundred rows and is a page load
    # paying for the whole table at a hundred thousand.
    create_index table_for(SearchProbe), [:probed_at]
  end

  def rollback
    drop_index table_for(SearchProbe), [:probed_at]
  end
end
