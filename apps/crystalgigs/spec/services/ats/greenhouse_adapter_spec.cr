require "../../spec_helper"

# The fixture was recorded from Greenhouse's real public board endpoint,
# GET https://boards-api.greenhouse.io/v1/boards/vercel/jobs?content=true.
# Only the `content` strings were truncated; every key and value shape is as
# the live API returned it.
describe CrystalGigs::Ats::Adapters::Greenhouse do
  adapter = CrystalGigs::Ats::Adapters::Greenhouse.new

  describe "#parse_postings" do
    it "maps a recorded board payload onto postings" do
      postings = adapter.parse_postings(ats_fixture("greenhouse_board.json"))

      postings.size.should eq(2)

      posting = postings.first
      posting.external_id.should eq("6136160004")
      posting.title.should eq("Account Executive, Commercial")
      posting.company_name.should eq("Vercel")
      posting.apply_url.should eq("https://job-boards.greenhouse.io/vercel/jobs/6136160004")
      posting.location.should eq("Hybrid - London")
      posting.job_type.should eq("full-time")
      posting.tags.should contain("account executive")
    end

    it "reads the publish time from first_published" do
      posting = adapter.parse_postings(ats_fixture("greenhouse_board.json")).first
      published_at = posting.published_at

      published_at.should_not be_nil
      published_at.not_nil!.to_utc.to_s("%Y-%m-%d").should eq("2026-08-06")
    end

    # Greenhouse ships HTML inside the JSON string with the markup itself
    # entity-escaped. Descriptions are rendered through `raw`, so nothing
    # bracket-shaped may survive.
    it "flattens the escaped HTML description to inert text" do
      posting = adapter.parse_postings(ats_fixture("greenhouse_board.json")).first

      posting.description.should_not be_empty
      posting.description.should_not contain("<")
      posting.description.should_not contain(">")
      posting.description.should_not contain("&lt;")
      posting.description.should contain("About Vercel")
    end

    it "raises when the payload is not a board" do
      expect_raises(CrystalGigs::Ats::ParseError, /jobs/) do
        adapter.parse_postings(%({"postings": []}))
      end
    end

    it "raises when the payload is not JSON at all" do
      expect_raises(CrystalGigs::Ats::ParseError) do
        adapter.parse_postings("<html>maintenance</html>")
      end
    end

    it "skips entries missing the fields a posting cannot do without" do
      payload = %({"jobs": [{"id": 1, "title": "No URL"}, {"id": 2, "title": "Fine", "absolute_url": "https://example.com/2"}]})

      postings = adapter.parse_postings(payload)

      postings.size.should eq(1)
      postings.first.external_id.should eq("2")
    end

    it "marks a remote location as remote and tags it" do
      payload = %({"jobs": [{"id": 3, "title": "Engineer", "absolute_url": "https://example.com/3", "location": {"name": "Remote - US"}}]})

      posting = adapter.parse_postings(payload).first

      posting.remote.should be_true
      posting.tags.should contain("remote")
    end

    it "reads an employment type out of board metadata when the employer sets one" do
      payload = %({"jobs": [{"id": 4, "title": "Engineer", "absolute_url": "https://example.com/4", "metadata": [{"name": "Employment Type", "value": "Internship"}]}]})

      adapter.parse_postings(payload).first.job_type.should eq("internship")
    end
  end

  describe "#fetch_postings" do
    it "requests the public board endpoint and parses the answer" do
      client = RecordedAtsClient.new
      client.stub_get("boards-api.greenhouse.io/v1/boards/acme/jobs", ats_fixture("greenhouse_board.json"))

      postings = adapter.fetch_postings("acme", client)

      postings.size.should eq(2)
      client.last_request.url.should eq("https://boards-api.greenhouse.io/v1/boards/acme/jobs?content=true")
    end

    it "raises with the status when the board answers with an error" do
      client = RecordedAtsClient.new
      client.stub_get("boards-api.greenhouse.io", %({"error": "not found"}), status: 404)

      expect_raises(CrystalGigs::Ats::UpstreamError, /404/) do
        adapter.fetch_postings("nope", client)
      end
    end
  end

  describe "#submit_application" do
    payload = CrystalGigs::Ats::ApplicationPayload.new(
      full_name: "Ada Lovelace",
      email: "ada@example.com",
      phone: "555-0100",
      resume_url: "https://example.com/ada.pdf",
      cover_letter: "Numbers are my thing."
    )

    it "posts the candidate to the board job with basic auth" do
      client = RecordedAtsClient.new
      client.stub_post("boards-api.greenhouse.io/v1/boards/acme/jobs/999", %({"success": true, "id": 4242}))

      receipt = with_ats_env({"ATS_GREENHOUSE_API_KEY" => "gh-secret"}) do
        adapter.submit_application("acme", "999", payload, client)
      end

      receipt.reference.should eq("4242")

      request = client.last_request
      request.url.should eq("https://boards-api.greenhouse.io/v1/boards/acme/jobs/999")
      request.headers["Authorization"].should eq("Basic #{Base64.strict_encode("gh-secret:")}")

      body = request.body.not_nil!
      body.should contain("first_name=Ada")
      body.should contain("last_name=Lovelace")
      body.should contain("email=ada%40example.com")
      # The board API takes a resume file or resume_text. We hold a link.
      body.should contain("resume_text=Resume")
    end

    it "raises rather than reporting success when the board rejects it" do
      client = RecordedAtsClient.new
      client.stub_post("boards-api.greenhouse.io", %({"error": "boom"}), status: 500)

      with_ats_env({"ATS_GREENHOUSE_API_KEY" => "gh-secret"}) do
        expect_raises(CrystalGigs::Ats::UpstreamError, /500/) do
          adapter.submit_application("acme", "999", payload, client)
        end
      end
    end

    it "fails closed with the variable to set when no credential is configured" do
      client = RecordedAtsClient.new
      client.stub_post("boards-api.greenhouse.io", "{}")

      with_ats_env({"ATS_GREENHOUSE_API_KEY" => nil}) do
        expect_raises(CrystalGigs::AtsConfig::MissingCredential, /ATS_GREENHOUSE_API_KEY/) do
          adapter.submit_application("acme", "999", payload, client)
        end
      end
    end
  end
end
