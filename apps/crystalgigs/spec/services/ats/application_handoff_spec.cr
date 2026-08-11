require "../../spec_helper"

private def imported_job(connection : AtsConnection, external_id : String = "999") : Job
  JobFactory.create &.source(connection.provider)
    .external_id(external_id)
    .ats_connection_id(connection.id)
    .apply_url("https://job-boards.greenhouse.io/acme/jobs/#{external_id}")
    .apply_email(nil)
end

describe CrystalGigs::Ats::ApplicationHandoff do
  describe "#deliver over the ATS API" do
    it "records a delivered handoff when the provider accepts it" do
      connection = AtsConnectionFactory.create &.provider("greenhouse").board_token("acme")
      job = imported_job(connection)
      application = JobApplicationFactory.create &.job_id(job.id)

      client = RecordedAtsClient.new
      client.stub_post("boards-api.greenhouse.io", %({"success": true, "id": 77}))

      result = with_ats_env({"ATS_GREENHOUSE_API_KEY" => "gh-secret"}) do
        CrystalGigs::Ats::ApplicationHandoff.new(client).deliver(application, job)
      end

      result.delivered?.should be_true
      result.handoff_method.should eq(JobApplication::METHOD_ATS_API)
      result.handoff_reference.should eq("77")
      result.handoff_error.should be_nil
      result.handed_off_at.should_not be_nil
    end

    # The acceptance case. A rejected submission is a failure, recorded as one.
    # It deliberately does not fall through to a weaker channel: a lost
    # application must be loud.
    it "records a failed handoff when the provider rejects it" do
      connection = AtsConnectionFactory.create &.provider("greenhouse").board_token("acme")
      job = imported_job(connection)
      application = JobApplicationFactory.create &.job_id(job.id)

      client = RecordedAtsClient.new
      client.stub_post("boards-api.greenhouse.io", %({"error": "nope"}), status: 500)

      result = with_ats_env({"ATS_GREENHOUSE_API_KEY" => "gh-secret"}) do
        CrystalGigs::Ats::ApplicationHandoff.new(client).deliver(application, job)
      end

      result.failed?.should be_true
      result.delivered?.should be_false
      result.handoff_method.should eq(JobApplication::METHOD_ATS_API)
      result.handoff_error.not_nil!.should contain("500")
      result.candidate_message.should contain("could not deliver")
    end

    it "does not quietly email when the ATS submission failed" do
      connection = AtsConnectionFactory.create &.provider("greenhouse")
        .board_token("acme")
        .application_email("jobs@acme.example.com")
      job = imported_job(connection)
      application = JobApplicationFactory.create &.job_id(job.id)

      client = RecordedAtsClient.new
      client.stub_post("boards-api.greenhouse.io", "boom", status: 503)

      result = with_ats_env({
        "ATS_GREENHOUSE_API_KEY"     => "gh-secret",
        "ATS_APPLICATION_FROM_EMAIL" => "applications@crystalgigs.org",
      }) do
        CrystalGigs::Ats::ApplicationHandoff.new(client).deliver(application, job)
      end

      result.failed?.should be_true
      Carbon::DevAdapter.delivered_emails.should be_empty
    end

    it "keeps the failure visible in a query an operator can run" do
      connection = AtsConnectionFactory.create &.provider("greenhouse").board_token("acme")
      job = imported_job(connection)
      application = JobApplicationFactory.create &.job_id(job.id)

      client = RecordedAtsClient.new
      client.stub_post("boards-api.greenhouse.io", "boom", status: 500)

      with_ats_env({"ATS_GREENHOUSE_API_KEY" => "gh-secret"}) do
        CrystalGigs::Ats::ApplicationHandoff.new(client).deliver(application, job)
      end

      JobApplicationQuery.new.needs_attention.select_count.should eq(1)
    end
  end

  describe "#deliver by email" do
    it "emails the employer when the provider credential is not configured" do
      connection = AtsConnectionFactory.create &.provider("greenhouse")
        .board_token("acme")
        .application_email("jobs@acme.example.com")
      job = imported_job(connection)
      application = JobApplicationFactory.create &.job_id(job.id)

      client = RecordedAtsClient.new

      result = with_ats_env({
        "ATS_GREENHOUSE_API_KEY"     => nil,
        "ATS_APPLICATION_FROM_EMAIL" => "applications@crystalgigs.org",
      }) do
        CrystalGigs::Ats::ApplicationHandoff.new(client).deliver(application, job)
      end

      result.delivered?.should be_true
      result.handoff_method.should eq(JobApplication::METHOD_EMAIL)
      result.handoff_reference.should eq("jobs@acme.example.com")
      # The skipped API link is recorded even though the handoff succeeded.
      result.handoff_error.not_nil!.should contain("ATS_GREENHOUSE_API_KEY")

      delivered = Carbon::DevAdapter.delivered_emails
      delivered.size.should eq(1)
      delivered.first.to.first.address.should eq("jobs@acme.example.com")
      delivered.first.headers["Reply-To"].should eq(application.candidate_email)
    end

    it "emails the address on the posting for a direct posting" do
      job = JobFactory.create &.apply_email("hiring@example.com")
      application = JobApplicationFactory.create &.job_id(job.id)

      result = with_ats_env({"ATS_APPLICATION_FROM_EMAIL" => "applications@crystalgigs.org"}) do
        CrystalGigs::Ats::ApplicationHandoff.new(RecordedAtsClient.new).deliver(application, job)
      end

      result.delivered?.should be_true
      result.handoff_method.should eq(JobApplication::METHOD_EMAIL)
      Carbon::DevAdapter.delivered_emails.first.to.first.address.should eq("hiring@example.com")
    end

    # No sender is configured, so we do not invent one. The chain moves on and
    # says why.
    it "skips email and records the reason when no sender is configured" do
      job = JobFactory.create &.apply_email("hiring@example.com")
        .apply_url("https://example.com/apply")
      application = JobApplicationFactory.create &.job_id(job.id)

      result = with_ats_env({"ATS_APPLICATION_FROM_EMAIL" => nil}) do
        CrystalGigs::Ats::ApplicationHandoff.new(RecordedAtsClient.new).deliver(application, job)
      end

      result.referred?.should be_true
      result.handoff_error.not_nil!.should contain("ATS_APPLICATION_FROM_EMAIL")
      Carbon::DevAdapter.delivered_emails.should be_empty
    end
  end

  describe "#deliver by referral" do
    it "refers the candidate to the apply URL when there is nothing else" do
      job = JobFactory.create &.apply_email(nil).apply_url("https://example.com/apply")
      application = JobApplicationFactory.create &.job_id(job.id)

      result = CrystalGigs::Ats::ApplicationHandoff.new(RecordedAtsClient.new).deliver(application, job)

      result.referred?.should be_true
      result.delivered?.should be_false
      result.handoff_method.should eq(JobApplication::METHOD_APPLY_URL)
      result.handoff_reference.should eq("https://example.com/apply")
      result.candidate_message.should contain("could not submit")
    end

    it "fails when the posting offers no route at all" do
      job = JobFactory.create &.apply_email(nil).apply_url(nil)
      application = JobApplicationFactory.create &.job_id(job.id)

      result = CrystalGigs::Ats::ApplicationHandoff.new(RecordedAtsClient.new).deliver(application, job)

      result.failed?.should be_true
      result.handoff_method.should be_nil
      result.handoff_error.not_nil!.should contain("No handoff route")
    end
  end
end
