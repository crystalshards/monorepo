require "../spec_helper"

# The launch bar sits at the very top of every page, above the masthead,
# pointing at this site's own announcement, which lives here on CrystalBits.
describe "the announcement bar" do
  it "renders above the masthead, linking to this site's announcement at the configured origin" do
    response = BrowserClient.exec(Home::Index)

    response.status_code.should eq(200)
    # Asserted against SiteLinks.origin rather than a literal hostname, the
    # same discipline as the footer cross links: the spec default is a
    # localhost origin, so a hardcoded production URL would never match it.
    href = %(href="#{SiteLinks.origin(:crystalbits)}/posts/a-place-to-write-about-crystal")
    response.body.should contain(href)
    # The link names the announcement rather than saying "click here".
    response.body.should contain("A place to write about Crystal")
    response.body.should contain(%(data-announcement-slug="a-place-to-write-about-crystal"))

    bar = response.body.index(%(class="announcement-bar")).not_nil!
    masthead = response.body.index(%(class="site-header")).not_nil!
    bar.should be < masthead
  end

  it "leaves the skip link as the first thing in the body, ahead of the bar" do
    response = BrowserClient.exec(Home::Index)

    skip_link = response.body.index(%(class="skip-link")).not_nil!
    bar = response.body.index(%(class="announcement-bar")).not_nil!
    skip_link.should be < bar
  end

  it "renders complete without JavaScript, with the dismiss control present for the script to reveal" do
    response = BrowserClient.exec(Home::Index)

    response.body.should contain(%(data-announcement-bar="true"))
    response.body.should contain(%(data-announcement-dismiss="true"))
  end
end
