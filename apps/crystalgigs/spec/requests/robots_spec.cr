require "../spec_helper"

describe Robots::Show do
  it "allows the whole board and points at the sitemap" do
    response = BrowserClient.exec(Robots::Show)

    response.status_code.should eq(200)
    response.body.should contain("User-agent: *")
    response.body.should contain("Allow: /")
    response.body.should_not contain("Disallow")

    origin = Lucky::RouteHelper.settings.base_uri
    response.body.should contain("Sitemap: #{origin}/sitemap.xml")
  end
end
