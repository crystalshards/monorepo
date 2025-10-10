require "../../../spec_helper"

describe Api::SignIns::Create do
  pending "returns a token" do
    # TODO: Fix ApiClient/BrowserClient to send form-encoded data instead of JSON
    # See issue #49 for investigation details
    UserToken.stub_token("fake-token") do
      user = UserFactory.create

      response = ApiClient.exec(Api::SignIns::Create, user: valid_params(user))

      response.should send_json(200, token: "fake-token")
    end
  end

  pending "returns an error if credentials are invalid" do
    # TODO: Fix ApiClient/BrowserClient to send form-encoded data instead of JSON
    # See issue #49 for investigation details
    user = UserFactory.create
    invalid_params = valid_params(user).merge(password: "incorrect")

    response = ApiClient.exec(Api::SignIns::Create, user: invalid_params)

    response.should send_json(
      400,
      param: "password",
      details: "password is wrong"
    )
  end
end

private def valid_params(user : User)
  {
    email:    user.email,
    password: "password",
  }
end
