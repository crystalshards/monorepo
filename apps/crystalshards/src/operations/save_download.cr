class SaveDownload < Download::SaveOperation
  permit_columns :ip_address, :user_agent, :country_code, :downloaded_at

  before_save do
    validate_required shard_version_id, ip_address, downloaded_at
  end
end
