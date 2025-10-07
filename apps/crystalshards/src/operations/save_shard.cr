class SaveShard < Shard::SaveOperation
  permit_columns :name, :description, :repository_url, :homepage_url,
    :documentation_url, :license, :total_downloads, :github_stars,
    :github_forks, :last_synced_at

  before_save do
    validate_required name, repository_url
    validate_uniqueness_of name
  end
end
