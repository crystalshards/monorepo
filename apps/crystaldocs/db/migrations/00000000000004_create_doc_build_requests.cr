class CreateDocBuildRequests::V00000000000004 < Avram::Migrator::Migration::V1
  def migrate
    create table_for(DocBuildRequest) do
      primary_key id : Int64
      add_timestamps

      add package_name : String
      add version : String

      # pending -> building -> succeeded | failed. See DocBuildRequest.
      add status : String, default: "pending"

      # When this combination was last put on the queue. Distinct from
      # created_at, which records the first time anyone asked for it.
      add requested_at : Time

      # Written by the builder, not by the web process.
      add started_at : Time?
      add finished_at : Time?
      add failed_at : Time?
      add last_error : String?

      # Enqueue count, not JoobQ's internal retry count. Incremented only when
      # the retry floor lets a failed build back onto the queue.
      add attempts : Int32, default: 0

      # The JoobQ job id of the most recent enqueue, so a stuck build can be
      # traced from a docs page to the queue without guessing.
      add job_id : String?
    end

    # This constraint is what makes lazy building idempotent, and it is the
    # reason the enqueue is an INSERT ... ON CONFLICT rather than a SELECT
    # followed by an INSERT. Two readers hitting the same cold version at the
    # same moment both find no row and both try to insert; the database picks
    # one winner and the loser gets zero rows back, so exactly one build is
    # queued. A check-then-insert in application code loses that race
    # precisely under the traffic that makes it matter.
    create_index table_for(DocBuildRequest), [:package_name, :version], unique: true

    # The pending page and the retry floor both look rows up by status.
    create_index table_for(DocBuildRequest), [:status]
  end

  def rollback
    drop table_for(DocBuildRequest)
  end
end
