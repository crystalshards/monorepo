require "../../spec_helper"

describe About::Show do
  # The masthead links here from every page. Before this route existed the
  # link 404'd site-wide, so the route existing at all is the thing under test.
  it "renders the about page" do
    response = BrowserClient.exec(About::Show)

    response.status.should eq(HTTP::Status.new(200))
    response.body.should contain("How a page gets here")
  end

  it "does not depend on any documentation being indexed" do
    response = BrowserClient.exec(About::Show)

    response.status.should eq(HTTP::Status.new(200))
  end

  # The page's whole claim is provenance, so it has to name the pipeline it
  # describes rather than gesturing at one.
  it "names the generator the documentation is built from" do
    response = BrowserClient.exec(About::Show)

    response.body.should contain("crystal docs --format=json")
  end

  # The standard library shipping as an ordinary package is a product
  # invariant, and the page links to it. If CORE_PACKAGE is ever renamed this
  # spec fails rather than the page growing a dead link.
  it "points at the standard library by its package name" do
    response = BrowserClient.exec(About::Show)

    response.body.should contain("/docs/#{CrystalDocs::CORE_PACKAGE}")
  end

  it "is reachable at the path the header advertises" do
    About::Show.path.should eq("/about")
  end
end
