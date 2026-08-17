require "../spec_helper"

# Sponsorship is copied byte-identical into every app's config/, so this spec
# is the same in each: it exercises the shared mechanism, not anything
# app-specific. See config/sponsorship.cr for why unset is a legitimate state
# in every environment, production included, while a set-but-malformed value
# fails at boot.
describe Sponsorship do
  describe ".parse" do
    it "accepts an absolute https URL" do
      Sponsorship.parse("https://github.com/sponsors/crystalshards").host
        .should eq("github.com")
    end

    it "strips surrounding whitespace" do
      Sponsorship.parse("  https://thebushido.co/sponsor  ").to_s
        .should eq("https://thebushido.co/sponsor")
    end

    # A relative or scheme-less value parses without complaint and would then
    # fail at click time in a reader's browser, so it is rejected at boot
    # with the variable named.
    it "refuses a bare hostname, naming the variable" do
      message = expect_raises(Sponsorship::InvalidDestination) do
        Sponsorship.parse("thebushido.co/sponsor")
      end.message.to_s

      message.should contain("SPONSORSHIP_URL")
      message.should contain("thebushido.co/sponsor")
    end

    it "refuses a scheme that is not http or https" do
      expect_raises(Sponsorship::InvalidDestination) do
        Sponsorship.parse("ftp://thebushido.co/sponsor")
      end
    end

    # https:///nowhere parses with neither error nor host, and absolute? only
    # proves a scheme is present.
    it "refuses a URL with no host" do
      expect_raises(Sponsorship::InvalidDestination) do
        Sponsorship.parse("https:///nowhere")
      end
    end
  end

  describe ".open?" do
    # The property is writable for specs; the boot value in test is nil, so
    # clearing it afterward is restoring it.
    after_each do
      Sponsorship.destination = nil
    end

    it "is false when there is no destination" do
      Sponsorship.destination = nil

      Sponsorship.open?.should be_false
    end

    it "is true when there is one" do
      Sponsorship.destination = Sponsorship.parse("https://thebushido.co/sponsor")

      Sponsorship.open?.should be_true
    end
  end
end
