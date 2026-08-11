class DocBuildRequestFactory < Avram::Factory
  def initialize
    package_name "sample-package-#{sequence("build-request-package")}"
    version "1.0.0"
    status DocBuildRequest::PENDING
    requested_at Time.utc
    attempts 1
  end

  # The builder's half of the row. Set failed_at, because that is the column
  # the retry floor measures from.
  def failed(at : Time, message : String = "crystal docs exited 1")
    status DocBuildRequest::FAILED
    started_at at - 2.minutes
    finished_at at
    failed_at at
    last_error message
  end

  def succeeded(at : Time = Time.utc)
    status DocBuildRequest::SUCCEEDED
    started_at at - 2.minutes
    finished_at at
  end
end
