require "../../spec_helper"

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
end
