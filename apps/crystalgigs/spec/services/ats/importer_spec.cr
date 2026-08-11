require "../../spec_helper"

private def board_payload(*jobs : String) : String
  %({"jobs": [#{jobs.join(",")}]})
end

# A board the employer emptied.
private def empty_board : String
  %({"jobs": []})
end

private def greenhouse_job(id : String, title : String = "Crystal Engineer") : String
  <<-JSON
  {
    "id": #{id},
    "title": "#{title}",
    "absolute_url": "https://job-boards.greenhouse.io/acme/jobs/#{id}",
    "location": {"name": "Denver, CO"},
    "content": "&lt;p&gt;Work on #{title}.&lt;/p&gt;",
    "departments": [{"name": "Engineering"}]
  }
  JSON
end

describe CrystalGigs::Ats::Importer do
  describe "#sync" do
    it "creates a job for every posting on the board" do
      connection = AtsConnectionFactory.create &.provider("greenhouse").board_token("acme")
      client = RecordedAtsClient.new
      client.stub_get("boards-api.greenhouse.io", board_payload(greenhouse_job("1"), greenhouse_job("2")))

      report = CrystalGigs::Ats::Importer.new(client).sync(connection)

      report.ok?.should be_true
      report.fetched.should eq(2)
      report.created.should eq(2)
      JobQuery.new.from_connection(connection).select_count.should eq(2)
    end

    it "stamps provenance so the posting can be traced back to its board" do
      connection = AtsConnectionFactory.create &.provider("greenhouse").board_token("acme")
      client = RecordedAtsClient.new
      client.stub_get("boards-api.greenhouse.io", board_payload(greenhouse_job("1")))

      CrystalGigs::Ats::Importer.new(client).sync(connection)

      job = JobQuery.new.from_connection(connection).first
      job.source.should eq("greenhouse")
      job.external_id.should eq("1")
      job.imported?.should be_true
      job.ats_connection_id.should eq(connection.id)
    end

    it "uses the connection's company name when the provider ships none" do
      connection = AtsConnectionFactory.create &.provider("lever")
        .board_token("acme")
        .company_name("Acme Crystal")
      client = RecordedAtsClient.new
      client.stub_get("api.lever.co", ats_fixture("lever_postings.json"))

      CrystalGigs::Ats::Importer.new(client).sync(connection)

      JobQuery.new.from_connection(connection).first.company_name.should eq("Acme Crystal")
    end

    # The acceptance case: importing the same posting twice must update, never
    # duplicate. The dedupe key is (source, external_id).
    it "updates an existing posting on re-sync instead of duplicating it" do
      connection = AtsConnectionFactory.create &.provider("greenhouse").board_token("acme")
      client = RecordedAtsClient.new
      importer = CrystalGigs::Ats::Importer.new(client)

      client.stub_get("boards-api.greenhouse.io", board_payload(greenhouse_job("1", "Crystal Engineer")))
      first = importer.sync(connection)

      client.stub_get("boards-api.greenhouse.io", board_payload(greenhouse_job("1", "Senior Crystal Engineer")))
      second = importer.sync(connection)

      first.created.should eq(1)
      second.created.should eq(0)
      second.updated.should eq(1)

      jobs = JobQuery.new.from_connection(connection).to_a
      jobs.size.should eq(1)
      jobs.first.title.should eq("Senior Crystal Engineer")
    end

    it "keeps the same row across a re-sync" do
      connection = AtsConnectionFactory.create &.provider("greenhouse").board_token("acme")
      client = RecordedAtsClient.new
      client.stub_get("boards-api.greenhouse.io", board_payload(greenhouse_job("1")))
      importer = CrystalGigs::Ats::Importer.new(client)

      importer.sync(connection)
      original_id = JobQuery.new.from_connection(connection).first.id
      importer.sync(connection)

      JobQuery.new.from_connection(connection).first.id.should eq(original_id)
    end

    # The other acceptance case: a posting the employer took down upstream is
    # delisted rather than left advertising a job that no longer exists.
    it "delists a posting that disappeared from the board" do
      connection = AtsConnectionFactory.create &.provider("greenhouse").board_token("acme")
      client = RecordedAtsClient.new
      importer = CrystalGigs::Ats::Importer.new(client)

      client.stub_get("boards-api.greenhouse.io", board_payload(greenhouse_job("1"), greenhouse_job("2")))
      importer.sync(connection)

      client.stub_get("boards-api.greenhouse.io", board_payload(greenhouse_job("1")))
      report = importer.sync(connection)

      report.delisted.should eq(1)

      removed = JobQuery.new.for_import(connection, "2").first
      removed.delisted?.should be_true
      removed.active.should be_false

      kept = JobQuery.new.for_import(connection, "1").first
      kept.delisted?.should be_false
      kept.active.should be_true
    end

    it "does not delist postings belonging to another connection" do
      acme = AtsConnectionFactory.create &.provider("greenhouse").board_token("acme")
      other = AtsConnectionFactory.create &.provider("lever").board_token("other")

      client = RecordedAtsClient.new
      client.stub_get("api.lever.co", ats_fixture("lever_postings.json"))
      CrystalGigs::Ats::Importer.new(client).sync(other)

      client.stub_get("boards-api.greenhouse.io", board_payload(greenhouse_job("1")))
      CrystalGigs::Ats::Importer.new(client).sync(acme)

      JobQuery.new.from_connection(other).to_a.each do |job|
        job.delisted?.should be_false
      end
    end

    # Greenhouse and Lever both mint platform-wide unique ids, so this cannot
    # bite today. It is specced because the adapter boundary invites a third
    # ATS, and a provider that numbers postings per board would otherwise let
    # one employer's sync take over another employer's row.
    it "keeps two boards apart when they reuse the same posting id" do
      acme = AtsConnectionFactory.create &.provider("greenhouse")
        .board_token("acme")
        .company_name("Acme Crystal")
      rival = AtsConnectionFactory.create &.provider("greenhouse")
        .board_token("rival")
        .company_name("Rival Crystal")

      client = RecordedAtsClient.new
      client.stub_get("/boards/acme/jobs", board_payload(greenhouse_job("1", "Acme Engineer")))
      client.stub_get("/boards/rival/jobs", board_payload(greenhouse_job("1", "Rival Engineer")))

      importer = CrystalGigs::Ats::Importer.new(client)
      importer.sync(acme)
      importer.sync(rival)

      JobQuery.new.for_import(acme, "1").first.title.should eq("Acme Engineer")
      JobQuery.new.for_import(rival, "1").first.title.should eq("Rival Engineer")
      JobQuery.new.for_import(acme, "1").first.ats_connection_id.should eq(acme.id)
      JobQuery.new.for_import(rival, "1").first.ats_connection_id.should eq(rival.id)
    end

    it "relists a posting that came back onto the board" do
      connection = AtsConnectionFactory.create &.provider("greenhouse").board_token("acme")
      client = RecordedAtsClient.new
      importer = CrystalGigs::Ats::Importer.new(client)

      client.stub_get("boards-api.greenhouse.io", board_payload(greenhouse_job("1")))
      importer.sync(connection)

      client.stub_get("boards-api.greenhouse.io", empty_board)
      importer.sync(connection)
      JobQuery.new.for_import(connection, "1").first.delisted?.should be_true

      client.stub_get("boards-api.greenhouse.io", board_payload(greenhouse_job("1")))
      report = importer.sync(connection)

      report.relisted.should eq(1)
      restored = JobQuery.new.for_import(connection, "1").first
      restored.delisted?.should be_false
      restored.active.should be_true
    end

    it "leaves postings created on the board itself alone" do
      direct = JobFactory.create
      connection = AtsConnectionFactory.create &.provider("greenhouse").board_token("acme")
      client = RecordedAtsClient.new
      client.stub_get("boards-api.greenhouse.io", empty_board)

      CrystalGigs::Ats::Importer.new(client).sync(connection)

      unchanged = JobQuery.new.id(direct.id).first
      unchanged.delisted?.should be_false
      unchanged.active.should be_true
      unchanged.source.should eq(Job::SOURCE_DIRECT)
    end

    it "records the sync on the connection" do
      connection = AtsConnectionFactory.create &.provider("greenhouse").board_token("acme")
      client = RecordedAtsClient.new
      client.stub_get("boards-api.greenhouse.io", board_payload(greenhouse_job("1")))

      CrystalGigs::Ats::Importer.new(client).sync(connection)

      reloaded = AtsConnectionQuery.new.id(connection.id).first
      reloaded.last_synced_at.should_not be_nil
      reloaded.last_sync_error.should be_nil
      reloaded.last_sync_summary.not_nil!.should contain("created 1")
    end

    it "reports a board failure instead of raising, and records it" do
      connection = AtsConnectionFactory.create &.provider("greenhouse").board_token("acme")
      client = RecordedAtsClient.new
      client.stub_get("boards-api.greenhouse.io", "gateway timeout", status: 504)

      report = CrystalGigs::Ats::Importer.new(client).sync(connection)

      report.ok?.should be_false
      report.error.not_nil!.should contain("504")

      reloaded = AtsConnectionQuery.new.id(connection.id).first
      reloaded.last_sync_error.not_nil!.should contain("504")
      reloaded.last_sync_failed?.should be_true
    end

    it "does not delist anything when the board could not be reached" do
      connection = AtsConnectionFactory.create &.provider("greenhouse").board_token("acme")
      client = RecordedAtsClient.new
      importer = CrystalGigs::Ats::Importer.new(client)

      client.stub_get("boards-api.greenhouse.io", board_payload(greenhouse_job("1")))
      importer.sync(connection)

      client.stub_get("boards-api.greenhouse.io", "down", status: 500)
      importer.sync(connection)

      JobQuery.new.for_import(connection, "1").first.delisted?.should be_false
    end
  end

  describe "#sync_all" do
    it "syncs every active connection and skips inactive ones" do
      active = AtsConnectionFactory.create &.provider("greenhouse").board_token("acme")
      AtsConnectionFactory.create &.provider("lever").board_token("dormant").active(false)

      client = RecordedAtsClient.new
      client.stub_get("boards-api.greenhouse.io", board_payload(greenhouse_job("1")))

      reports = CrystalGigs::Ats::Importer.new(client).sync_all

      reports.size.should eq(1)
      reports.first.board_token.should eq(active.board_token)
    end
  end
end
