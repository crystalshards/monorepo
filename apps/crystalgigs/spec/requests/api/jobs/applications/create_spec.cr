require "../../../../spec_helper"

private def application_params(email : String = "ada@example.com")
  {
    job_application: {
      candidate_name:  "Ada Lovelace",
      candidate_email: email,
      resume_url:      "https://example.com/ada.pdf",
      cover_letter:    "I would like to apply.",
    },
  }
end

describe Api::Jobs::Applications::Create do
  it "tells the candidate their application was sent when the ATS took it" do
    connection = AtsConnectionFactory.create &.provider("greenhouse").board_token("acme")
    job = JobFactory.create &.source("greenhouse")
      .external_id("999")
      .ats_connection_id(connection.id)
      .apply_email(nil)

    client = RecordedAtsClient.new
    client.stub_post("boards-api.greenhouse.io", %({"success": true, "id": 5}))

    response = with_ats_env({"ATS_GREENHOUSE_API_KEY" => "gh-secret"}) do
      with_ats_client(client) do
        ApiClient.exec(Api::Jobs::Applications::Create.with(job_id: job.id), **application_params)
      end
    end

    response.status_code.should eq(201)
    body = JSON.parse(response.body)
    body["submitted"].should eq(true)
    body["status"].should eq("delivered")
    body["method"].should eq("ats_api")
  end

  # The acceptance case: a failed handoff must never read as a successful one.
  it "does not tell the candidate they applied when the handoff failed" do
    connection = AtsConnectionFactory.create &.provider("greenhouse").board_token("acme")
    job = JobFactory.create &.source("greenhouse")
      .external_id("999")
      .ats_connection_id(connection.id)
      .apply_email(nil)
      .apply_url("https://job-boards.greenhouse.io/acme/jobs/999")

    client = RecordedAtsClient.new
    client.stub_post("boards-api.greenhouse.io", %({"error": "nope"}), status: 500)

    response = with_ats_env({"ATS_GREENHOUSE_API_KEY" => "gh-secret"}) do
      with_ats_client(client) do
        ApiClient.exec(Api::Jobs::Applications::Create.with(job_id: job.id), **application_params)
      end
    end

    response.status_code.should eq(502)

    body = JSON.parse(response.body)
    body["submitted"].should eq(false)
    body["status"].should eq("failed")
    body["message"].as_s.should contain("could not deliver")
    # The candidate is given somewhere to go rather than a dead end.
    body["next_step"].should eq("https://job-boards.greenhouse.io/acme/jobs/999")

    stored = JobApplicationQuery.new.for_job(job).first
    stored.failed?.should be_true
    stored.handoff_error.not_nil!.should contain("500")
  end

  it "is explicit that a referral is not a submitted application" do
    job = JobFactory.create &.apply_email(nil).apply_url("https://example.com/apply")

    response = with_ats_client(RecordedAtsClient.new) do
      ApiClient.exec(Api::Jobs::Applications::Create.with(job_id: job.id), **application_params)
    end

    response.status_code.should eq(202)
    body = JSON.parse(response.body)
    body["submitted"].should eq(false)
    body["status"].should eq("referred")
    body["next_step"].should eq("https://example.com/apply")
  end

  it "records the application even when the handoff fails" do
    job = JobFactory.create &.apply_email(nil).apply_url(nil)

    with_ats_client(RecordedAtsClient.new) do
      ApiClient.exec(Api::Jobs::Applications::Create.with(job_id: job.id), **application_params)
    end

    JobApplicationQuery.new.for_job(job).select_count.should eq(1)
  end

  it "rejects an application with an invalid email" do
    job = JobFactory.create

    response = with_ats_client(RecordedAtsClient.new) do
      ApiClient.exec(
        Api::Jobs::Applications::Create.with(job_id: job.id),
        **application_params(email: "not-an-email")
      )
    end

    response.status_code.should eq(422)
    JobApplicationQuery.new.for_job(job).select_count.should eq(0)
  end

  it "returns 404 for a job that does not exist" do
    response = ApiClient.exec(
      Api::Jobs::Applications::Create.with(job_id: 999_999_i64),
      **application_params
    )

    response.status_code.should eq(404)
  end

  it "refuses applications to a posting the employer delisted" do
    connection = AtsConnectionFactory.create &.provider("greenhouse").board_token("acme")
    job = JobFactory.create &.source("greenhouse")
      .external_id("gone")
      .ats_connection_id(connection.id)
      .delisted_at(Time.utc)
      .active(false)

    response = ApiClient.exec(Api::Jobs::Applications::Create.with(job_id: job.id), **application_params)

    response.status_code.should eq(410)
    JobApplicationQuery.new.for_job(job).select_count.should eq(0)
  end
end
