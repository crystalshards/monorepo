require "../../spec_helper"

describe Pricing::Show do
  # The footer has linked here from every page for as long as the footer has
  # existed. Before this route the link 404'd, on a product that charges money.
  it "renders the pricing page" do
    response = BrowserClient.exec(Pricing::Show)

    response.status_code.should eq(200)
    response.body.should contain("How it works")
  end

  it "is reachable at the path the footer advertises" do
    Pricing::Show.path.should eq("/pricing")
  end

  it "does not depend on any job being posted" do
    response = BrowserClient.exec(Pricing::Show)

    response.status_code.should eq(200)
  end

  # The commercial terms live in one module. If someone changes the price and
  # the page keeps quoting the old one, that is a page telling a customer the
  # wrong number, so the page is asserted against the module rather than
  # against a literal.
  it "quotes the price from the Pricing module" do
    response = BrowserClient.exec(Pricing::Show)

    response.body.should contain(::Pricing.price_label)
    response.body.should contain(::Pricing.summary)
  end

  it "states the posting duration from the Pricing module" do
    response = BrowserClient.exec(Pricing::Show)

    response.body.should contain(::Pricing.duration_days.to_s)
  end

  it "sends the reader to the posting form" do
    response = BrowserClient.exec(Pricing::Show)

    response.body.should contain(Jobs::New.path)
  end
end
