require "../../../../spec_helper"

private def connection_params(provider : String = "greenhouse", board_token : String = "acme")
  {
    ats_connection: {
      provider:          provider,
      board_token:       board_token,
      company_name:      "Acme Crystal",
      application_email: "jobs@acme.example.com",
    },
  }
end

private def greenhouse_board(id : String = "1", title : String = "Crystal Engineer") : String
  <<-JSON
  {"jobs": [{
    "id": #{id},
    "title": "#{title}",
    "absolute_url": "https://job-boards.greenhouse.io/acme/jobs/#{id}",
    "location": {"name": "Remote - US"},
    "content": "&lt;p&gt;Build things.&lt;/p&gt;"
  }]}
  JSON
end

describe Api::Ats::Connections::Create do
  it "registers a board and imports it immediately" do
    user = UserFactory.create
    client = RecordedAtsClient.new
    client.stub_get("boards-api.greenhouse.io", greenhouse_board)

    response = with_ats_client(client) do
      ApiClient.auth(user).exec(Api::Ats::Connections::Create, **connection_params)
    end

    response.status_code.should eq(201)
    body = JSON.parse(response.body)
    body["connection"]["provider"].should eq("greenhouse")
    body["connection"]["board_token"].should eq("acme")
    body["sync"]["ok"].should eq(true)
    body["sync"]["created"].should eq(1)

    connection = AtsConnectionQuery.new.for_board("greenhouse", "acme").first
    JobQuery.new.for_import(connection, "1").select_count.should eq(1)
  end

  it "requires authentication" do
    response = ApiClient.exec(Api::Ats::Connections::Create, **connection_params)

    response.status_code.should eq(401)
  end

  it "rejects a provider with no adapter" do
    user = UserFactory.create

    response = with_ats_client(RecordedAtsClient.new) do
      ApiClient.auth(user).exec(
        Api::Ats::Connections::Create,
        **connection_params(provider: "workday")
      )
    end

    response.status_code.should eq(422)
    JSON.parse(response.body)["errors"].as_a.size.should be > 0
  end

  it "updates the existing connection when the same board is registered again" do
    user = UserFactory.create
    client = RecordedAtsClient.new
    client.stub_get("boards-api.greenhouse.io", greenhouse_board)

    with_ats_client(client) do
      ApiClient.auth(user).exec(Api::Ats::Connections::Create, **connection_params)
      response = ApiClient.auth(user).exec(Api::Ats::Connections::Create, **connection_params)

      response.status_code.should eq(200)
    end

    AtsConnectionQuery.new.for_board("greenhouse", "acme").select_count.should eq(1)
  end

  it "refuses a board another account already registered" do
    owner = UserFactory.create
    intruder = UserFactory.create
    AtsConnectionFactory.create &.user_id(owner.id).provider("greenhouse").board_token("acme")

    response = with_ats_client(RecordedAtsClient.new) do
      ApiClient.auth(intruder).exec(Api::Ats::Connections::Create, **connection_params)
    end

    response.status_code.should eq(409)
  end

  it "reports a board that could not be read without losing the registration" do
    user = UserFactory.create
    client = RecordedAtsClient.new
    client.stub_get("boards-api.greenhouse.io", "nope", status: 404)

    response = with_ats_client(client) do
      ApiClient.auth(user).exec(Api::Ats::Connections::Create, **connection_params)
    end

    response.status_code.should eq(201)
    body = JSON.parse(response.body)
    body["sync"]["ok"].should eq(false)
    body["sync"]["error"].as_s.should contain("404")

    AtsConnectionQuery.new.for_board("greenhouse", "acme").select_count.should eq(1)
  end

  # Nothing secret is stored on the record, so nothing secret can be echoed.
  it "never returns a credential" do
    user = UserFactory.create
    client = RecordedAtsClient.new
    client.stub_get("boards-api.greenhouse.io", greenhouse_board)

    response = with_ats_env({"ATS_GREENHOUSE_API_KEY" => "gh-secret"}) do
      with_ats_client(client) do
        ApiClient.auth(user).exec(Api::Ats::Connections::Create, **connection_params)
      end
    end

    response.body.should_not contain("gh-secret")
  end
end
