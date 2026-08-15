require "../../spec_helper"

private def extract_json_ld(body : String) : JSON::Any
  match = body.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/)
  match.should_not be_nil
  JSON.parse(match.not_nil![1])
end

describe Jobs::Show do
  it "renders a published job" do
    job = JobFactory.create &.title("Crystal Developer")
      .description("We need someone who knows Crystal.")
      .published_at(Time.utc)
      .active(true)

    response = BrowserClient.exec(Jobs::Show.with(job_id: job.id))

    response.status_code.should eq(200)
    response.body.should contain("Crystal Developer")
    response.body.should contain("We need someone who knows Crystal.")
  end

  # A job description is written by whoever posts the job, and the page puts it
  # through `raw`. It was previously passed unescaped, so a description could
  # execute script on this origin for every visitor who opened the posting.
  describe "a description is untrusted input" do
    it "does not let a description inject a script tag" do
      job = JobFactory.create &.title("Hostile Posting")
        .description(%(Great role.\n<script>alert("xss")</script>\nApply now.))
        .published_at(Time.utc)
        .active(true)

      response = BrowserClient.exec(Jobs::Show.with(job_id: job.id))

      response.status_code.should eq(200)
      response.body.should_not contain("<script>alert")
      response.body.should contain("&lt;script&gt;")
      # The surrounding prose still renders, so escaping has not eaten the
      # description along with the payload.
      response.body.should contain("Great role.")
      response.body.should contain("Apply now.")
    end

    it "does not let a description inject an event handler" do
      job = JobFactory.create &.title("Hostile Handler")
        .description(%(<img src=x onerror="alert(1)">))
        .published_at(Time.utc)
        .active(true)

      response = BrowserClient.exec(Jobs::Show.with(job_id: job.id))

      response.body.should_not contain(%(<img src=x onerror=))
      response.body.should contain("&lt;img")
    end

    it "still turns newlines into line breaks" do
      job = JobFactory.create &.title("Multi Line")
        .description("First line.\nSecond line.")
        .published_at(Time.utc)
        .active(true)

      response = BrowserClient.exec(Jobs::Show.with(job_id: job.id))

      response.body.should contain("First line.<br>Second line.")
    end
  end

  describe "JobPosting structured data" do
    it "emits complete, valid JSON-LD for a published, open, on-site posting" do
      job = JobFactory.create &.title("Senior Crystal Developer")
        .description("Build things.\nShip things.")
        .company_name("Crystal Corp")
        .company_url("https://crystalcorp.example.com")
        .location("San Francisco, CA")
        .remote(false)
        .job_type("full-time")
        .salary_min(150_000)
        .salary_max(200_000)
        .salary_currency("USD")
        .apply_url("https://crystalcorp.example.com/apply")
        .apply_email(nil)
        .published_at(Time.utc)
        .expires_at(Time.utc + 45.days)
        .active(true)

      response = BrowserClient.exec(Jobs::Show.with(job_id: job.id))
      json = extract_json_ld(response.body)

      json["@context"].as_s.should eq("https://schema.org/")
      json["@type"].as_s.should eq("JobPosting")

      # Plain job title: no company name and no location riding along in it.
      json["title"].as_s.should eq("Senior Crystal Developer")
      json["title"].as_s.should_not contain("Crystal Corp")
      json["title"].as_s.should_not contain("San Francisco")

      # The full HTML description, escaped the same way the visible page is.
      json["description"].as_s.should eq("Build things.<br>Ship things.")

      Time.parse_rfc3339(json["datePosted"].as_s).should eq(job.published_at)
      Time.parse_rfc3339(json["validThrough"].as_s).should eq(job.expires_at)

      json["employmentType"].as_s.should eq("FULL_TIME")

      json["identifier"]["name"].as_s.should eq("CrystalGigs")
      json["identifier"]["value"].as_s.should eq(job.id.to_s)

      json["hiringOrganization"]["name"].as_s.should eq("Crystal Corp")
      json["hiringOrganization"]["sameAs"].as_s.should eq("https://crystalcorp.example.com")

      address = json["jobLocation"]["address"]
      address["@type"].as_s.should eq("PostalAddress")
      address["addressLocality"].as_s.should eq("San Francisco")
      address["addressRegion"].as_s.should eq("CA")
      address["addressCountry"].as_s.should eq("US")
      json.as_h.has_key?("jobLocationType").should be_false

      salary = json["baseSalary"]
      salary["currency"].as_s.should eq("USD")
      salary["value"]["minValue"].as_i.should eq(150_000)
      salary["value"]["maxValue"].as_i.should eq(200_000)
      salary["value"]["unitText"].as_s.should eq("YEAR")

      # Only a mailto instruction counts as direct apply; an external URL
      # hands the candidate off to a site this board knows nothing about.
      json["directApply"].as_bool.should eq(false)
    end

    it "emits TELECOMMUTE and applicant location requirements for a remote posting, never a fabricated address" do
      job = JobFactory.create &.title("Remote Crystal Engineer")
        .location(nil)
        .remote(true)
        .apply_url(nil)
        .apply_email("jobs@example.com")
        .published_at(Time.utc)
        .expires_at(Time.utc + 30.days)
        .active(true)

      response = BrowserClient.exec(Jobs::Show.with(job_id: job.id))
      json = extract_json_ld(response.body)

      json["jobLocationType"].as_s.should eq("TELECOMMUTE")
      json["applicantLocationRequirements"]["@type"].as_s.should eq("Country")
      json.as_h.has_key?("jobLocation").should be_false

      # An email-only apply path is the one thing Google's own definition of
      # directApply credits without an in-site form: instructions for
      # reaching the employer directly.
      json["directApply"].as_bool.should eq(true)
    end

    it "does not carry a jobLocation when the location cannot be honestly parsed into a real address" do
      job = JobFactory.create &.location("Remote - anywhere")
        .remote(false)
        .published_at(Time.utc)
        .active(true)

      response = BrowserClient.exec(Jobs::Show.with(job_id: job.id))
      json = extract_json_ld(response.body)

      json.as_h.has_key?("jobLocation").should be_false
      json.as_h.has_key?("jobLocationType").should be_false
    end

    it "emits no JobPosting markup for an unpublished or unpaid posting" do
      job = JobFactory.create &.published_at(nil).expires_at(nil)

      response = BrowserClient.exec(Jobs::Show.with(job_id: job.id))

      response.status_code.should eq(200)
      response.body.should_not contain("application/ld+json")
    end

    it "cannot be broken out of by a hostile title" do
      job = JobFactory.create &.title(%(Engineer</script><script>alert(1)</script>))
        .published_at(Time.utc)
        .active(true)

      response = BrowserClient.exec(Jobs::Show.with(job_id: job.id))

      response.body.should_not contain("</script><script>alert(1)</script>")
      # The title still round-trips correctly for anything that actually
      # parses the JSON, proving the escaping is cosmetic to HTML and
      # invisible to a real consumer.
      extract_json_ld(response.body)["title"].as_s.should contain("<script>alert(1)</script>")
    end
  end

  describe "a posting that has stopped being open" do
    it "returns Gone for an expired posting rather than advertising it as still open" do
      job = JobFactory.create &.published_at(Time.utc - 40.days).expires_at(Time.utc - 10.days)

      response = BrowserClient.exec(Jobs::Show.with(job_id: job.id))

      response.status_code.should eq(410)
      response.body.should_not contain("application/ld+json")
    end

    it "returns Gone for a delisted posting" do
      job = JobFactory.create &.published_at(Time.utc).active(false)

      response = BrowserClient.exec(Jobs::Show.with(job_id: job.id))

      response.status_code.should eq(410)
    end

    it "still renders normally for a posting that is merely a draft, never having been published" do
      job = JobFactory.create &.published_at(nil).active(true)

      response = BrowserClient.exec(Jobs::Show.with(job_id: job.id))

      response.status_code.should eq(200)
    end
  end
end
