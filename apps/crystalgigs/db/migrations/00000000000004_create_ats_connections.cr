class CreateAtsConnections::V00000000000004 < Avram::Migrator::Migration::V1
  def migrate
    create table_for(AtsConnection) do
      primary_key id : Int64
      add_timestamps

      add_belongs_to user : User, on_delete: :cascade

      add provider : String
      add board_token : String
      add company_name : String
      add company_url : String?
      add application_email : String?
      add active : Bool, default: true
      add last_synced_at : Time?
      add last_sync_error : String?
      add last_sync_summary : String?
    end

    # One connection per board. Re-registering the same board updates the
    # existing row instead of creating a second source of the same postings.
    create_index table_for(AtsConnection), [:provider, :board_token],
      unique: true, name: "ats_connections_provider_board_token_idx"
    create_index table_for(AtsConnection), [:active], name: "ats_connections_active_idx"
  end

  def rollback
    drop_index table_for(AtsConnection), name: "ats_connections_active_idx"
    drop_index table_for(AtsConnection), name: "ats_connections_provider_board_token_idx"
    drop table_for(AtsConnection)
  end
end
