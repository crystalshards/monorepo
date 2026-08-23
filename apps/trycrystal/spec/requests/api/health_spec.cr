require "../../spec_helper"

describe Api::Health::Show do
  it "reports ok with the runner configured" do
    response = ApiClient.exec(Api::Health::Show)

    response.status_code.should eq 200
    body = JSON.parse(response.body)
    body["status"].should eq "ok"
    body["services"]["runner"].should eq "configured"
  end
end
