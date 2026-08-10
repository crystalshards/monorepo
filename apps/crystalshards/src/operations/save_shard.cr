class SaveShard < Shard::SaveOperation
  permit_columns :name, :description, :repository_url, :homepage_url,
    :documentation_url, :license, :total_downloads, :github_stars,
    :github_forks, :last_synced_at, :provider, :repository_type,
    :readme_content

  before_save do
    set_default_values
    validate_required name, repository_url, provider, repository_type
    validate_uniqueness_of name
    validate_url_format
  end

  private def set_default_values
    total_downloads.value ||= 0_i64
    provider.value ||= "github"
    repository_type.value ||= "git"
  end

  private def validate_url_format
    if url = repository_url.value
      unless url.starts_with?("http://") || url.starts_with?("https://")
        repository_url.add_error "must be a valid URL starting with http:// or https://"
      end
    end
  end
end
