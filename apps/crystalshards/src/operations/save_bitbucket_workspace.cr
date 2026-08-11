class SaveBitbucketWorkspace < BitbucketWorkspace::SaveOperation
  permit_columns :slug, :enabled, :note, :last_seen_at, :last_error, :repository_count

  before_save do
    slug.value = slug.value.try(&.strip.downcase)
    enabled.value = true if enabled.value.nil?
    repository_count.value ||= 0

    validate_required slug
    # A slug is interpolated into an API path, so a malformed one is refused
    # here rather than normalised into something that resolves elsewhere.
    validate_format_of slug, with: BitbucketWorkspace::SLUG_FORMAT,
      message: "must be a Bitbucket workspace id: letters, numbers, hyphens and underscores"
    validate_uniqueness_of slug
    truncate_error
  end

  MAX_ERROR_LENGTH = 500

  private def truncate_error
    if message = last_error.value
      last_error.value = message[0, MAX_ERROR_LENGTH] if message.size > MAX_ERROR_LENGTH
    end
  end
end
