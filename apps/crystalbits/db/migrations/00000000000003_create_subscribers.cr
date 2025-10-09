class CreateSubscribers::V00000000000003 < Avram::Migrator::Migration::V1
  def migrate
    create table_for(Subscriber) do
      primary_key id : Int64

      add email : String, unique: true, index: true
      add confirmed : Bool, default: false
      add confirmation_token : String?, unique: true, index: true
      add confirmed_at : Time?
      add unsubscribed_at : Time?

      add_timestamps
    end
  end

  def rollback
    drop table_for(Subscriber)
  end
end
