require "../../../spec_helper"

describe Api::Jobs::Show do
  it "returns a job by id" do
    job = JobFactory.create &.title("Crystal Developer")

    response = ApiClient.exec(Api::Jobs::Show.with(id: job.id))

    response.status_code.should eq(200)
    body = JSON.parse(response.body)

    body["id"].should eq(job.id)
    body["title"].should eq("Crystal Developer")
    body["company_name"].should eq(job.company_name)
  end

  it "returns 404 for non-existent job" do
    response = ApiClient.exec(Api::Jobs::Show.with(id: 99999))

    response.status_code.should eq(404)
    body = JSON.parse(response.body)
    body["error"].should eq("Job not found")
  end
end
