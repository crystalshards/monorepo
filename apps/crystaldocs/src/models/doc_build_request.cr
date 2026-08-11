# One row per (package, version) combination anyone has ever asked to see.
#
# Documentation is built on first request rather than ahead of time, so the
# absence of an artifact is ambiguous on its own: nobody has asked yet, a build
# is running, or a build ran and failed. Registering the combination turns that
# ambiguity into a fact the reader can be shown and the enqueue logic can
# reason about.
#
# Two processes write this row, and they write disjoint halves:
#
#   crystaldocs (web)  package_name, version, status -> pending, requested_at,
#                      attempts, job_id
#   crystalshards      status -> building | succeeded | failed, started_at,
#   (BuildDocsWorker)  finished_at, failed_at, last_error
#
# The builder half is written over a second connection, mirroring how this app
# already reads the registry. Neither side writes the other's columns.
class DocBuildRequest < BaseModel
  # Queued, nothing has picked it up yet.
  PENDING = "pending"
  # A worker has claimed it and is cloning and compiling.
  BUILDING = "building"
  # The artifact is in storage.
  SUCCEEDED = "succeeded"
  # The build ran and produced nothing usable. Subject to the retry floor.
  FAILED = "failed"

  table do
    column package_name : String
    column version : String
    column status : String
    column requested_at : Time
    column started_at : Time?
    column finished_at : Time?
    column failed_at : Time?
    column last_error : String?
    column attempts : Int32
    column job_id : String?
  end

  def pending? : Bool
    status == PENDING
  end

  def building? : Bool
    status == BUILDING
  end

  def succeeded? : Bool
    status == SUCCEEDED
  end

  def failed? : Bool
    status == FAILED
  end

  # Queued or running: the reader should wait rather than be told anything is
  # wrong.
  def in_flight? : Bool
    pending? || building?
  end
end
