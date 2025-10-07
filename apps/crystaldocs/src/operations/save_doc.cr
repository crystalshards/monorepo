class SaveDoc < Doc::SaveOperation
  permit_columns package_name, current_version, description, repository_url, total_views, last_updated_at

  before_save do
    validate_required package_name
    validate_uniqueness_of package_name
    total_views.value ||= 0_i64
  end
end
