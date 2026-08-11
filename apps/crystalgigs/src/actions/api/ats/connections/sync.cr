# On-demand sync of one registered board. The scheduled path is the
# `ats.sync` task; this is the same importer, triggered by the employer.
class Api::Ats::Connections::Sync < ApiAction
  post "/api/ats/connections/:connection_id/sync" do
    connection = AtsConnectionQuery.new.id(connection_id.to_i64).first?

    if connection.nil? || connection.user_id != current_user.id
      # Same answer either way: a wrong owner learns nothing about whether the
      # connection exists.
      json(
        ErrorSerializer.new(
          message: "Connection not found.",
          details: "No ATS connection with that id belongs to you."
        ),
        status: 404
      )
    else
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
      }, status: report.ok? ? 200 : 502)
    end
  end
end
