class SaveDependency < Dependency::SaveOperation
  permit_columns :name, :version_requirement, :scope

  before_save do
    validate_required shard_version_id, name, version_requirement, scope
  end
end
