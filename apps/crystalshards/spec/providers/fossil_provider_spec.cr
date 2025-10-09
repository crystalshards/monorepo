require "../spec_helper"

describe FossilProvider do
  describe "#repository_type" do
    it "returns fossil" do
      provider = FossilProvider.new("https://example.com/repo.fossil")
      provider.repository_type.should eq("fossil")
    end
  end

  describe "#provider_name" do
    it "returns fossil" do
      provider = FossilProvider.new("https://example.com/repo.fossil")
      provider.provider_name.should eq("fossil")
    end
  end

  describe "#supports_api?" do
    it "returns false" do
      provider = FossilProvider.new("https://example.com/repo.fossil")
      provider.supports_api?.should be_false
    end
  end

  describe "#fetch_metadata" do
    it "returns basic metadata" do
      provider = FossilProvider.new("https://example.com/repo.fossil")
      metadata = provider.fetch_metadata

      metadata.should_not be_nil
      metadata.try(&.stars).should be_nil
      metadata.try(&.forks).should be_nil
    end
  end
end
