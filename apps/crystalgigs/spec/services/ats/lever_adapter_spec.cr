require "../../spec_helper"

# The fixture was recorded from Lever's real public postings endpoint,
# GET https://api.lever.co/v0/postings/leverdemo?mode=json. Two postings were
# kept, one with a salary range and one without, because the live board
# returns both. Only the long description strings were truncated.
describe CrystalGigs::Ats::Adapters::Lever do
  adapter = CrystalGigs::Ats::Adapters::Lever.new

  describe "#parse_postings" do
    it "maps a recorded postings payload onto postings" do
      postings = adapter.parse_postings(ats_fixture("lever_postings.json"))

      postings.size.should eq(2)

      posting = postings.find! { |candidate| candidate.title == "AbelsonTaylor Writer" }
      posting.external_id.should eq("33538a2f-d27d-4a96-8f05-fa4b0e4d940e")
      posting.apply_url.should eq("https://jobs.lever.co/leverdemo/33538a2f-d27d-4a96-8f05-fa4b0e4d940e/apply")
      posting.location.should eq("Arlington, TX")
      posting.job_type.should eq("full-time")
      posting.tags.should contain("customer success")
      posting.tags.should contain("professional services")
    end

    # Lever's feed has no company field at all, which is why Posting allows a
    # nil company and the importer falls back to the connection.
    it "leaves the company name unset" do
      adapter.parse_postings(ats_fixture("lever_postings.json")).each do |posting|
        posting.company_name.should be_nil
      end
    end

    it "reads the salary range when the posting carries one" do
      posting = adapter.parse_postings(ats_fixture("lever_postings.json"))
        .find! { |candidate| candidate.title == "Account Executive" }

      posting.salary_min.should eq(10000)
      posting.salary_max.should eq(125000)
      posting.salary_currency.should eq("USD")
    end

    it "converts the epoch millisecond createdAt to a time" do
      posting = adapter.parse_postings(ats_fixture("lever_postings.json"))
        .find! { |candidate| candidate.title == "AbelsonTaylor Writer" }

      posting.published_at.should eq(Time.unix_ms(1553186035299))
    end

    it "treats workplaceType remote as remote" do
      postings = adapter.parse_postings(ats_fixture("lever_postings.json"))

      postings.find! { |posting| posting.title == "Account Executive" }.remote.should be_true
      postings.find! { |posting| posting.title == "AbelsonTaylor Writer" }.remote.should be_false
    end

    it "folds the description, the titled lists and the trailing section into inert text" do
      posting = adapter.parse_postings(ats_fixture("lever_postings.json"))
        .find! { |candidate| candidate.title == "AbelsonTaylor Writer" }

      posting.description.should contain("Qualifications")
      posting.description.should contain("be smart")
      posting.description.should_not contain("<")
      posting.description.should_not contain(">")
    end

    it "raises when the payload is not an array" do
      expect_raises(CrystalGigs::Ats::ParseError, /array/) do
        adapter.parse_postings(%({"postings": []}))
      end
    end

    it "normalises Lever's commitment vocabulary onto the board's job types" do
      payload = %([
        {"id": "a", "text": "One", "hostedUrl": "https://jobs.lever.co/x/a", "categories": {"commitment": "Internship"}},
        {"id": "b", "text": "Two", "hostedUrl": "https://jobs.lever.co/x/b", "categories": {"commitment": "Part-time"}},
        {"id": "c", "text": "Three", "hostedUrl": "https://jobs.lever.co/x/c", "categories": {"commitment": "Contract - Remote"}},
        {"id": "d", "text": "Four", "hostedUrl": "https://jobs.lever.co/x/d", "categories": {"commitment": "Regular Full Time (Salary)"}}
      ])

      types = adapter.parse_postings(payload).map(&.job_type)

      types.should eq(["internship", "part-time", "contract", "full-time"])
    end

    it "falls back to the hosted URL when there is no apply URL" do
      payload = %([{"id": "a", "text": "One", "hostedUrl": "https://jobs.lever.co/x/a"}])

      adapter.parse_postings(payload).first.apply_url.should eq("https://jobs.lever.co/x/a")
    end
  end

  describe "#fetch_postings" do
    it "requests the public postings endpoint" do
      client = RecordedAtsClient.new
      client.stub_get("api.lever.co/v0/postings/acme", ats_fixture("lever_postings.json"))

      adapter.fetch_postings("acme", client).size.should eq(2)
      client.last_request.url.should eq("https://api.lever.co/v0/postings/acme?mode=json")
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

    it "posts a multipart application with the key as a query parameter" do
      client = RecordedAtsClient.new
      client.stub_post("api.lever.co/v0/postings/acme/posting-1", %({"ok": true, "applicationId": "app-9"}))

      receipt = with_ats_env({"ATS_LEVER_API_KEY" => "lever-secret"}) do
        adapter.submit_application("acme", "posting-1", payload, client)
      end

      receipt.reference.should eq("app-9")

      request = client.last_request
      request.url.should contain("key=lever-secret")
      request.headers["Content-Type"].should contain("multipart/form-data")

      body = request.body.not_nil!
      body.should contain("Ada Lovelace")
      body.should contain("ada@example.com")
      body.should contain("urls[Resume]")
    end

    # Lever authenticates with a query parameter, so a Lever URL is a
    # credential. It must never reach a message intact.
    it "keeps the key out of the failure message" do
      client = RecordedAtsClient.new
      client.stub_post("api.lever.co", %({"ok": false}), status: 500)

      with_ats_env({"ATS_LEVER_API_KEY" => "lever-secret"}) do
        error = expect_raises(CrystalGigs::Ats::UpstreamError, /500/) do
          adapter.submit_application("acme", "posting-1", payload, client)
        end

        message = error.message.not_nil!
        message.should_not contain("lever-secret")
        message.should contain("key=REDACTED")
      end
    end

    it "fails closed with the variable to set when no credential is configured" do
      client = RecordedAtsClient.new
      client.stub_post("api.lever.co", "{}")

      with_ats_env({"ATS_LEVER_API_KEY" => nil}) do
        expect_raises(CrystalGigs::AtsConfig::MissingCredential, /ATS_LEVER_API_KEY/) do
          adapter.submit_application("acme", "posting-1", payload, client)
        end
      end
    end
  end
end
