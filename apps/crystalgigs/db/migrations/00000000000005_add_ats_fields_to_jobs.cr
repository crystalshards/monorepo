class AddAtsFieldsToJobs::V00000000000005 < Avram::Migrator::Migration::V1
  def migrate
    alter table_for(Job) do
      # "direct" for postings created on CrystalGigs, otherwise the ATS
      # provider key ("greenhouse", "lever").
      add source : String, default: "direct"
      # Provider-side identifier. Together with source this is the dedupe key
      # for imports.
      add external_id : String?
      # Set when a posting disappeared from the employer's board upstream.
      add delisted_at : Time?

      add_belongs_to ats_connection : AtsConnection?, on_delete: :nullify
    end

    # The dedupe key is scoped to the connection, not to the provider.
    #
    # Greenhouse and Lever both mint ids that are unique across their whole
    # platform, so (source, external_id) would work for them. It is still the
    # wrong key: a third adapter is a new class by design, and a provider that
    # numbers postings per board ("1", "2", "3") would let one employer's sync
    # overwrite another employer's row, including its ats_connection_id.
    # Scoping to the connection also keeps rows orphaned by a deleted
    # connection (ats_connection_id nullified) from blocking a re-registration
    # of the same board on the unique index.
    #
    # NULLs are distinct in Postgres, so direct postings are unaffected.
    create_index table_for(Job), [:ats_connection_id, :external_id],
      unique: true, name: "jobs_ats_connection_external_id_idx"
    create_index table_for(Job), [:delisted_at], name: "jobs_delisted_at_idx"
  end

  def rollback
    drop_index table_for(Job), name: "jobs_delisted_at_idx"
    drop_index table_for(Job), name: "jobs_ats_connection_external_id_idx"

    alter table_for(Job) do
      remove_belongs_to :ats_connection
      remove :delisted_at
      remove :external_id
      remove :source
    end
  end
end
