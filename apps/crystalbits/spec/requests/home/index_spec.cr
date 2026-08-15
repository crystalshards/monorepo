require "../../spec_helper"

describe Home::Index do
  it "renders the homepage" do
    response = BrowserClient.exec(Home::Index)

    response.status_code.should eq(200)
    response.body.should contain("CrystalBits")
  end

  # The footer carries the collective's mark, a line naming the collective
  # as this site's maintainer, this repository's license, and a link to each
  # sibling site. The cross links are asserted against SiteLinks.origin
  # rather than a literal hostname, so this fails the way it should if the
  # footer ever goes back to a hardcoded URL: the spec default is a
  # localhost origin, and a hardcoded production hostname would not match
  # it.
  it "renders the Bushido Collective seal, maintainer line, license, and cross links" do
    response = BrowserClient.exec(Home::Index)

    response.body.should contain(%(class="tbc-seal"))
    response.body.should contain(%(aria-label="Forged by The Bushido Collective"))
    response.body.should contain("https://thebushido.co")
    response.body.should contain("The Bushido Collective builds and maintains this site.")

    response.body.should contain("Apache License 2.0")
    response.body.should contain("https://github.com/crystalshards/monorepo/blob/main/LICENSE")

    response.body.should contain(SiteLinks.origin(:crystalshards))
    response.body.should contain(SiteLinks.origin(:crystaldocs))
    response.body.should contain(SiteLinks.origin(:crystalgigs))
  end
end
