class SaveDocVersion < DocVersion::SaveOperation
  permit_columns doc_id, version, published_at, build_status, storage_path, file_count, total_size, metadata

  before_save do
    validate_required doc_id, version, published_at, build_status, storage_path
    validate_inclusion_of build_status, in: ["pending", "building", "success", "failed"]
  end
end
