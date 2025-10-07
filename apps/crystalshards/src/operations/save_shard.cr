class SaveShard < Shard::SaveOperation
  permit_columns :name, :description, :repository_url, :homepage_url,
    :documentation_url, :license, :total_downloads, :github_stars,
    :github_forks, :last_synced_at

  before_save do
    validate_required name, repository_url
    validate_uniqueness_of name
    validate_url_format
    total_downloads.value ||= 0_i64
  end

  private def validate_url_format
    if url = repository_url.value
      unless url.starts_with?("http://") || url.starts_with?("https://")
        repository_url.add_error "must be a valid URL starting with http:// or https://"
      end
    end
  end
end
