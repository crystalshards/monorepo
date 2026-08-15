require "../spec_helper"

# Nothing about the board may silently disqualify it from Google Jobs or any
# equivalent feature: no page may tell a crawler to skip it, whether through
# the page itself or a response header, and the machine-readable posting
# markup may only ever live on the one page per job Google's own docs say it
# belongs on.
describe "crawlability of the jobs board" do
  it "never sends a noindex directive from a job's own page, in the markup or a header" do
    job = JobFactory.create &.published_at(Time.utc).active(true)

    response = BrowserClient.exec(Jobs::Show.with(job_id: job.id))

    response.body.should_not contain("noindex")
    response.headers["X-Robots-Tag"]?.should be_nil
  end

  it "never sends a noindex directive from the jobs list, in the markup or a header" do
    response = BrowserClient.exec(Jobs::Index)

    response.body.should_not contain("noindex")
    response.headers["X-Robots-Tag"]?.should be_nil
  end

  # Google's own troubleshooting docs call this out by name: "A job listing
  # page... has JobPosting structured data on the page" is a policy
  # violation on its own, independent of whether the postings it lists are
  # otherwise correct.
  it "never puts JobPosting markup on the jobs list, which shows many postings at once" do
    JobFactory.create &.published_at(Time.utc).active(true)

    response = BrowserClient.exec(Jobs::Index)

    response.body.should_not contain("application/ld+json")
  end

  it "does not let robots.txt block the jobs board or the sitemap" do
    response = BrowserClient.exec(Robots::Show)

    response.body.should_not match(/Disallow:\s*\/jobs/)
    response.body.should_not match(/Disallow:\s*\/sitemap/)
  end
end
