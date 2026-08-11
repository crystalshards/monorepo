class CreateJobApplications::V00000000000006 < Avram::Migrator::Migration::V1
  def migrate
    create table_for(JobApplication) do
      primary_key id : Int64
      add_timestamps

      add_belongs_to job : Job, on_delete: :cascade

      add candidate_name : String
      add candidate_email : String
      add candidate_phone : String?
      add resume_url : String?
      add cover_letter : String?

      # How the application reached the employer: ats_api, email, apply_url,
      # or nil while still pending.
      add handoff_method : String?
      # pending, delivered, referred, failed.
      add handoff_status : String, default: "pending"
      # Provider-side identifier or destination, when the handoff produced one.
      add handoff_reference : String?
      # Why a handoff failed, plus notes about links of the chain that were
      # skipped. Kept so a failed handoff is visible rather than silent.
      add handoff_error : String?
      add handed_off_at : Time?
    end

    create_index table_for(JobApplication), [:handoff_status], name: "job_applications_handoff_status_idx"
    create_index table_for(JobApplication), [:candidate_email], name: "job_applications_candidate_email_idx"
  end

  def rollback
    drop_index table_for(JobApplication), name: "job_applications_candidate_email_idx"
    drop_index table_for(JobApplication), name: "job_applications_handoff_status_idx"
    drop table_for(JobApplication)
  end
end
