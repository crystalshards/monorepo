class MakeApplyUrlOptional::V00000000000003 < Avram::Migrator::Migration::V1
  # SaveJob validates "at least one of apply_url or apply_email", and the job
  # form treats the apply URL as optional, but the column was created NOT NULL.
  # That made an apply-by-email-only posting impossible to save.
  def migrate
    make_optional table_for(Job), :apply_url
  end

  def rollback
    make_required table_for(Job), :apply_url
  end
end
