require "../../../spec_helper"

describe Api::Jobs::Create do
  it "creates a new job with valid params" do
    params = {
      job: {
        title:        "Crystal Developer",
        description:  "Looking for Crystal expertise",
        company_name: "Crystal Corp",
        job_type:     "full-time",
        apply_url:    "https://example.com/apply",
      },
    }

    response = ApiClient.exec(Api::Jobs::Create, **params)

    response.status_code.should eq(201)
    body = JSON.parse(response.body)

    body["title"].should eq("Crystal Developer")
    body["company_name"].should eq("Crystal Corp")
    body["job_type"].should eq("full-time")
  end

  it "returns errors for invalid params" do
    params = {
      job: {
        title:       "Crystal Developer",
        description: "Looking for Crystal expertise",
      },
    }

    response = ApiClient.exec(Api::Jobs::Create, **params)

    response.status_code.should eq(422)
    body = JSON.parse(response.body)
    body["errors"].as_a.size.should be > 0
  end

  it "validates job_type is valid" do
    params = {
      job: {
        title:        "Crystal Developer",
        description:  "Looking for Crystal expertise",
        company_name: "Crystal Corp",
        job_type:     "invalid-type",
        apply_url:    "https://example.com/apply",
      },
    }

    response = ApiClient.exec(Api::Jobs::Create, **params)

    response.status_code.should eq(422)
  end

  it "validates salary range" do
    params = {
      job: {
        title:        "Crystal Developer",
        description:  "Looking for Crystal expertise",
        company_name: "Crystal Corp",
        job_type:     "full-time",
        apply_url:    "https://example.com/apply",
        salary_min:   150000,
        salary_max:   100000,
      },
    }

    response = ApiClient.exec(Api::Jobs::Create, **params)

    response.status_code.should eq(422)
  end
end
