# An ATS connection as an employer sees it.
#
# The board token is public, so it is echoed back. Nothing secret exists on
# the record to leak: API keys live in the environment, never in the database.
class AtsConnectionSerializer < BaseSerializer
  def initialize(@connection : AtsConnection)
  end

  def render
    {
      id:                @connection.id,
      provider:          @connection.provider,
      board_token:       @connection.board_token,
      board_url:         board_url,
      company_name:      @connection.company_name,
      company_url:       @connection.company_url,
      application_email: @connection.application_email,
      active:            @connection.active,
      last_synced_at:    @connection.last_synced_at,
      last_sync_summary: @connection.last_sync_summary,
      last_sync_error:   @connection.last_sync_error,
      created_at:        @connection.created_at,
    }
  end

  private def board_url : String?
    @connection.board_url
  rescue CrystalGigs::Ats::UnknownProviderError
    nil
  end
end
