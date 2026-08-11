# Scheduled inbound sync: `lucky ats.sync`.
#
# Run it from cron or a scheduler. It walks every active connection, and one
# broken board does not stop the rest. Exits non-zero when any board failed so
# a scheduler can alert on it.
class Ats::Sync < LuckyTask::Task
  summary "Import job postings from every registered ATS board"

  def call
    connections = AtsConnectionQuery.new.active_only.recent.to_a

    if connections.empty?
      puts "No active ATS connections registered."
      return
    end

    importer = CrystalGigs::Ats::Importer.new
    failures = 0

    connections.each do |connection|
      report = importer.sync(connection)
      label = "#{connection.provider}/#{connection.board_token}"

      if report.ok?
        puts "  #{label}: #{report.summary}"
      else
        failures += 1
        STDERR.puts "  #{label}: #{report.summary}"
      end
    end

    puts "Synced #{connections.size} connection(s), #{failures} failed."
    exit(1) if failures > 0
  end
end
