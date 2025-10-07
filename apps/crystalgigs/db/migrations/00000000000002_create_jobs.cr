class CreateJobs::V00000000000002 < Avram::Migrator::Migration::V1
  def migrate
    create table_for(Job) do
      primary_key id : Int64
      add_timestamps

      add title : String
      add description : String
      add company_name : String
      add company_url : String?
      add location : String?
      add remote : Bool, default: false
      add job_type : String
      add salary_min : Int32?
      add salary_max : Int32?
      add salary_currency : String, default: "USD"
      add apply_url : String
      add apply_email : String?
      add tags : Array(String), default: [] of String
      add published_at : Time?
      add expires_at : Time?
      add featured : Bool, default: false
      add active : Bool, default: true
    end

    create_index table_for(Job), [:published_at], name: "jobs_published_at_idx"
    create_index table_for(Job), [:expires_at], name: "jobs_expires_at_idx"
    create_index table_for(Job), [:job_type], name: "jobs_job_type_idx"
    create_index table_for(Job), [:remote], name: "jobs_remote_idx"
    create_index table_for(Job), [:featured], name: "jobs_featured_idx"
    create_index table_for(Job), [:active], name: "jobs_active_idx"
  end

  def rollback
    drop_index table_for(Job), name: "jobs_active_idx"
    drop_index table_for(Job), name: "jobs_featured_idx"
    drop_index table_for(Job), name: "jobs_remote_idx"
    drop_index table_for(Job), name: "jobs_job_type_idx"
    drop_index table_for(Job), name: "jobs_expires_at_idx"
    drop_index table_for(Job), name: "jobs_published_at_idx"
    drop table_for(Job)
  end
end
