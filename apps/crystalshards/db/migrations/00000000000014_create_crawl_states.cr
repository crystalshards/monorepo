# Per-host crawl state: the cursor a sweep resumes from, and the record of how
# the last sweep ended.
#
# Both halves are here on purpose. A cursor without an outcome lets a crawl
# resume but leaves nobody able to say whether the registry's view of a host is
# complete; an outcome without a cursor means every interruption restarts from
# the first page, which on a rate-limited host means never finishing.
class CreateCrawlStates::V00000000000014 < Avram::Migrator::Migration::V1
  def migrate
    create table_for(CrawlState) do
      primary_key id : Int64
      add_timestamps
      # One row per host, and the crawler upserts on this, so the database is
      # what stops two sweeps of the same host from each keeping their own idea
      # of where the cursor is.
      add host : String, unique: true, index: true
      add status : String, default: "idle"
      add cursor : String?
      add last_started_at : Time?
      add last_completed_at : Time?
      add stop_reason : String?
      add last_error : String?
      add discovered_count : Int64, default: 0
      add updated_count : Int64, default: 0
      add unavailable_count : Int64, default: 0
      add skipped_count : Int64, default: 0
      add failed_count : Int64, default: 0
    end
  end

  def rollback
    drop table_for(CrawlState)
  end
end
