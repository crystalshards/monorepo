# An employer's registered applicant tracking system job board.
#
# The board token is public: it is the same token that appears in the
# employer's own job board URL. Secrets never live here, they come from
# `CrystalGigs::AtsConfig`.
class AtsConnection < BaseModel
  table do
    belongs_to user : User

    column provider : String
    column board_token : String
    column company_name : String
    column company_url : String?
    column application_email : String?
    column active : Bool = true
    column last_synced_at : Time?
    column last_sync_error : String?
    column last_sync_summary : String?

    has_many jobs : Job
  end

  # The adapter that speaks this connection's provider.
  # Raises `CrystalGigs::Ats::UnknownProviderError` for an unregistered key.
  def adapter : CrystalGigs::Ats::Adapter
    CrystalGigs::Ats::Registry.fetch(provider)
  end

  def board_url : String
    adapter.board_url(board_token)
  end

  def last_sync_failed? : Bool
    !last_sync_error.nil?
  end
end
