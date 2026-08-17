require "../../spec_helper"

describe Sponsor::Show do
  # The page's only input is a writable config property, so each spec sets
  # the state it needs and it is cleared afterward, the same discipline the
  # job ad component specs use. The boot value in test is nil, so clearing
  # is restoring.
  after_each do
    Sponsorship.destination = nil
  end

  it "renders at the path the footer advertises" do
    Sponsor::Show.path.should eq("/sponsor")
  end

  it "renders with a funding destination configured" do
    Sponsorship.destination = Sponsorship.parse("https://sponsor.example.test/collective")

    response = BrowserClient.exec(Sponsor::Show)

    response.status.should eq(HTTP::Status.new(200))
    response.body.should contain(%(href="https://sponsor.example.test/collective"))
    response.body.should contain("sponsor.example.test")
    response.body.should contain("Become a sponsor")
  end

  # Unset is a legitimate state, production included: the destination is a
  # decision the owner has not made yet, and the page has to say so plainly
  # rather than render a button wired to nowhere.
  it "renders an honest not-open state without a destination" do
    Sponsorship.destination = nil

    response = BrowserClient.exec(Sponsor::Show)

    response.status.should eq(HTTP::Status.new(200))
    response.body.should contain("Sponsorship is not open yet")
    response.body.should_not contain("Become a sponsor")
  end

  # For a registry, what money cannot buy is the whole credibility question,
  # so the statement is asserted rather than left to drift.
  it "states what sponsorship does not buy" do
    response = BrowserClient.exec(Sponsor::Show)

    response.body.should contain("What sponsorship does not buy")
    response.body.should contain(
      "Sponsorship does not buy influence over what this registry indexes, ranks, or shows."
    )
    response.body.should contain("There are no sponsored listings and no paid placement at any tier")
    response.body.should contain("it changes on this page first")
  end

  # The case for sponsoring rests on naming the real cost drivers rather
  # than inventing figures, so the page has to name them.
  it "names the infrastructure the money pays for" do
    response = BrowserClient.exec(Sponsor::Show)

    response.body.should contain("Cloud Run")
    response.body.should contain("Cloud SQL")
    response.body.should contain("Object storage")
    response.body.should contain("build sandbox")
  end

  it "names the maintainer and links to the collective" do
    response = BrowserClient.exec(Sponsor::Show)

    response.body.should contain("The Bushido Collective")
    response.body.should contain("https://thebushido.co")
    response.body.should contain(%(class="tbc-seal"))
  end

  it "is linked from the footer" do
    response = BrowserClient.exec(Sponsor::Show)

    response.body.should contain(%(href="/sponsor"))
  end
end
