class SaveOwner < Owner::SaveOperation
  permit_columns :role

  before_save do
    validate_required user_id, shard_id, role
  end
end
