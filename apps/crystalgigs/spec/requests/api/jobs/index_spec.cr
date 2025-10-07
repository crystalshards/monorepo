require "../../../spec_helper"

describe Api::Jobs::Index do
  it "returns a list of active jobs" do
    job1 = JobFactory.create &.title("Crystal Developer")
    job2 = JobFactory.create &.title("Lucky Framework Expert")
    JobFactory.create &.active(false)

    response = ApiClient.exec(Api::Jobs::Index)

    response.status_code.should eq(200)
    body = JSON.parse(response.body)

    body["jobs"].as_a.size.should eq(2)
    body["total"].should eq(2)
  end

  it "filters by job_type" do
    JobFactory.create &.job_type("full-time")
    JobFactory.create &.job_type("contract")

    response = ApiClient.exec(Api::Jobs::Index, job_type: "contract")

    body = JSON.parse(response.body)
    body["jobs"].as_a.size.should eq(1)
    body["jobs"][0]["job_type"].should eq("contract")
  end

  it "filters by remote" do
    JobFactory.create &.remote(true)
    JobFactory.create &.remote(false)

    response = ApiClient.exec(Api::Jobs::Index, remote: "true")

    body = JSON.parse(response.body)
    body["jobs"].as_a.size.should eq(1)
    body["jobs"][0]["remote"].should eq(true)
  end

  it "searches by title, description, or company name" do
    JobFactory.create &.title("Senior Crystal Developer")
    JobFactory.create &.company_name("Crystal Corp")
    JobFactory.create &.title("JavaScript Developer")

    response = ApiClient.exec(Api::Jobs::Index, q: "Crystal")

    body = JSON.parse(response.body)
    body["jobs"].as_a.size.should eq(2)
  end

  it "paginates results" do
    25.times { JobFactory.create }

    response = ApiClient.exec(Api::Jobs::Index, page: "2", per_page: "10")

    body = JSON.parse(response.body)
    body["jobs"].as_a.size.should eq(10)
    body["page"].should eq(2)
    body["per_page"].should eq(10)
    body["total"].should eq(25)
  end

  it "filters out expired jobs" do
    JobFactory.create &.expires_at(Time.utc + 1.day)
    JobFactory.create &.expires_at(Time.utc - 1.day)

    response = ApiClient.exec(Api::Jobs::Index)

    body = JSON.parse(response.body)
    body["jobs"].as_a.size.should eq(1)
  end
end
