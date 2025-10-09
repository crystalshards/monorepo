require "../spec_helper"

describe MercurialProvider do
  describe "#repository_type" do
    it "returns mercurial" do
      provider = MercurialProvider.new("https://example.com/repo.hg")
      provider.repository_type.should eq("mercurial")
    end
  end

  describe "#provider_name" do
    it "returns mercurial" do
      provider = MercurialProvider.new("https://example.com/repo.hg")
      provider.provider_name.should eq("mercurial")
    end
  end

  describe "#supports_api?" do
    it "returns false" do
      provider = MercurialProvider.new("https://example.com/repo.hg")
      provider.supports_api?.should be_false
    end
  end

  describe "#fetch_metadata" do
    it "returns basic metadata" do
      provider = MercurialProvider.new("https://example.com/repo.hg")
      metadata = provider.fetch_metadata

      metadata.should_not be_nil
      metadata.try(&.stars).should be_nil
      metadata.try(&.forks).should be_nil
    end
  end
end
