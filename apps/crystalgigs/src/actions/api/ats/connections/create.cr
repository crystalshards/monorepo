# Registers an employer's ATS job board.
#
# The board token is the public token from the employer's own board URL. No
# secret is accepted here: outbound API credentials are environment
# configuration, so nothing an employer posts can become one.
#
# Registering syncs immediately, because an employer who has just connected a
# board wants to see their postings, not a promise about a scheduled run.
class Api::Ats::Connections::Create < ApiAction
  post "/api/ats/connections" do
    existing = existing_connection

    if existing && existing.user_id != current_user.id
      json(
        ErrorSerializer.new(
          message: "That board is already registered.",
          details: "Another account registered this provider and board token."
        ),
        status: 409
      )
    else
      save(existing) do |operation, connection|
        if connection
          report = CrystalGigs::Ats::Importer.new.sync(connection)
          json({
            connection: AtsConnectionSerializer.new(
              AtsConnectionQuery.new.id(connection.id).first
            ),
            sync: {
              ok:       report.ok?,
              summary:  report.summary,
              fetched:  report.fetched,
              created:  report.created,
              updated:  report.updated,
              delisted: report.delisted,
              relisted: report.relisted,
              error:    report.error,
            },
          }, status: existing ? 200 : 201)
        else
          json({errors: operation.errors.map { |attr, msgs| {attr.to_s => msgs} }}, status: 422)
        end
      end
    end
  end

  # Re-registering a board updates it rather than failing on the unique index.
  private def save(existing : AtsConnection?, &)
    if existing
      SaveAtsConnection.update(existing, params) do |operation, connection|
        yield operation, connection
      end
    else
      SaveAtsConnection.create(params, user_id: current_user.id) do |operation, connection|
        yield operation, connection
      end
    end
  end

  private def existing_connection : AtsConnection?
    attributes = params.nested?(:ats_connection)
    provider = attributes["provider"]?
    board_token = attributes["board_token"]?
    return nil if provider.nil? || board_token.nil?

    AtsConnectionQuery.new.for_board(provider, board_token).first?
  end
end
