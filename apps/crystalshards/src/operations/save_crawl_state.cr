class SaveCrawlState < CrawlState::SaveOperation
  permit_columns :host, :status, :cursor, :last_started_at, :last_completed_at,
    :stop_reason, :last_error, :discovered_count, :updated_count,
    :unavailable_count, :skipped_count, :failed_count

  before_save do
    set_default_values
    validate_required host, status
    validate_inclusion_of status, in: [
      CrawlState::Status::IDLE,
      CrawlState::Status::RUNNING,
      CrawlState::Status::COMPLETED,
      CrawlState::Status::PARTIAL,
      CrawlState::Status::FAILED,
    ]
    # The unique index is the real guarantee. This is here so a second sweep of
    # a host that tries to create its own row gets a validation error naming the
    # problem, rather than a raw constraint violation from the driver.
    validate_uniqueness_of host
    truncate_error
  end

  private def set_default_values
    status.value ||= CrawlState::Status::IDLE
    discovered_count.value ||= 0_i64
    updated_count.value ||= 0_i64
    unavailable_count.value ||= 0_i64
    skipped_count.value ||= 0_i64
    failed_count.value ||= 0_i64
  end

  # A host can hand back a full HTML error page, and the point of this column is
  # to say what went wrong at a glance, not to archive the body.
  MAX_ERROR_LENGTH = 500

  private def truncate_error
    if message = last_error.value
      last_error.value = message[0, MAX_ERROR_LENGTH] if message.size > MAX_ERROR_LENGTH
    end
  end
end
