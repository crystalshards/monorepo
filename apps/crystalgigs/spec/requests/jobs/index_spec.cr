require "../../spec_helper"

describe Jobs::Index do
  it "renders the job listing page" do
    job1 = JobFactory.create &.title("Crystal Developer").published_at(Time.utc).active(true)
    job2 = JobFactory.create &.title("Lucky Framework Expert").published_at(Time.utc).active(true)

    response = BrowserClient.exec(Jobs::Index)

    response.status_code.should eq(200)
    response.body.should contain("Crystal Developer")
    response.body.should contain("Lucky Framework Expert")
  end

  it "filters by location" do
    JobFactory.create &.title("SF Job").location("San Francisco").published_at(Time.utc).active(true)
    JobFactory.create &.title("NY Job").location("New York").published_at(Time.utc).active(true)

    response = BrowserClient.exec(Jobs::Index.with(location: "San Francisco"))

    response.status_code.should eq(200)
    response.body.should contain("SF Job")
    response.body.should_not contain("NY Job")
  end

  it "filters by job type" do
    # Titles must not collide with the job-type dropdown option labels
    # ("Full Time", "Contract", ...) that the filter form always renders.
    JobFactory.create &.title("Permanent Position").job_type("full-time").published_at(Time.utc).active(true)
    JobFactory.create &.title("Short Term Engagement").job_type("contract").published_at(Time.utc).active(true)

    response = BrowserClient.exec(Jobs::Index.with(job_type: "contract"))

    response.status_code.should eq(200)
    response.body.should contain("Short Term Engagement")
    response.body.should_not contain("Permanent Position")
  end

  it "filters by remote" do
    JobFactory.create &.title("Remote Job").remote(true).published_at(Time.utc).active(true)
    JobFactory.create &.title("On-site Job").remote(false).published_at(Time.utc).active(true)

    response = BrowserClient.exec(Jobs::Index.with(remote: "true"))

    response.status_code.should eq(200)
    response.body.should contain("Remote Job")
    response.body.should_not contain("On-site Job")
  end

  it "searches jobs by query" do
    # The factory description and company name both mention Crystal, so the
    # excluded job must override them or it legitimately matches the search.
    JobFactory.create &.title("Crystal Developer").published_at(Time.utc).active(true)
    JobFactory.create &.title("Ruby Developer")
      .description("We are looking for an experienced Ruby developer.")
      .company_name("Ruby Corp")
      .apply_url("https://rubycorp.example.com/careers")
      .tags(["ruby", "backend"])
      .published_at(Time.utc).active(true)

    response = BrowserClient.exec(Jobs::Index.with(query: "Crystal"))

    response.status_code.should eq(200)
    response.body.should contain("Crystal Developer")
    response.body.should_not contain("Ruby Developer")
  end

  it "paginates results" do
    25.times do |i|
      JobFactory.create &.title("Job #{i}").published_at(Time.utc).active(true)
    end

    response = BrowserClient.exec(Jobs::Index.with(page: "2"))

    response.status_code.should eq(200)
    response.body.should contain("Page 2 of")
  end

  it "shows empty state when no jobs" do
    response = BrowserClient.exec(Jobs::Index)

    response.status_code.should eq(200)
    response.body.should contain("No jobs found")
  end

  it "only shows active and published jobs" do
    JobFactory.create &.title("Published").published_at(Time.utc).active(true)
    JobFactory.create &.title("Unpublished").published_at(nil).active(true)
    JobFactory.create &.title("Inactive").published_at(Time.utc).active(false)

    response = BrowserClient.exec(Jobs::Index)

    response.status_code.should eq(200)
    response.body.should contain("Published")
    response.body.should_not contain("Unpublished")
    response.body.should_not contain("Inactive")
  end

  it "filters out expired jobs" do
    JobFactory.create &.title("Active").published_at(Time.utc).expires_at(Time.utc + 1.day).active(true)
    JobFactory.create &.title("Expired").published_at(Time.utc).expires_at(Time.utc - 1.day).active(true)

    response = BrowserClient.exec(Jobs::Index)

    response.status_code.should eq(200)
    response.body.should contain("Active")
    response.body.should_not contain("Expired")
  end
end
