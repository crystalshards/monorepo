require "spec"
require "../../src/providers/provider_factory"

describe ProviderFactory do
  describe ".detect_provider_type" do
    it "detects github" do
      ProviderFactory.detect_provider_type("https://github.com/user/repo").should eq("github")
    end

    it "detects github SSH" do
      ProviderFactory.detect_provider_type("git@github.com:user/repo.git").should eq("github")
    end

    it "detects gitlab" do
      ProviderFactory.detect_provider_type("https://gitlab.com/user/repo").should eq("gitlab")
    end

    it "detects bitbucket" do
      ProviderFactory.detect_provider_type("https://bitbucket.org/user/repo").should eq("bitbucket")
    end

    it "detects codeberg" do
      ProviderFactory.detect_provider_type("https://codeberg.org/user/repo").should eq("codeberg")
    end

    it "detects git for .git URLs" do
      ProviderFactory.detect_provider_type("https://example.com/repo.git").should eq("git")
    end

    it "detects mercurial for .hg URLs" do
      ProviderFactory.detect_provider_type("https://example.com/repo.hg").should eq("mercurial")
    end

    it "detects fossil for .fossil URLs" do
      ProviderFactory.detect_provider_type("https://example.com/repo.fossil").should eq("fossil")
    end

    it "defaults to git for unknown URLs" do
      ProviderFactory.detect_provider_type("https://example.com/repo").should eq("git")
    end
  end

  describe ".detect_repository_type" do
    it "detects Git type for GitHub" do
      ProviderFactory.detect_repository_type("https://github.com/user/repo").should eq(ProviderFactory::RepositoryType::Git)
    end

    it "detects Git type for GitLab" do
      ProviderFactory.detect_repository_type("https://gitlab.com/user/repo").should eq(ProviderFactory::RepositoryType::Git)
    end

    it "detects Git type for generic .git URLs" do
      ProviderFactory.detect_repository_type("https://example.com/repo.git").should eq(ProviderFactory::RepositoryType::Git)
    end

    it "detects Mercurial type" do
      ProviderFactory.detect_repository_type("https://example.com/repo.hg").should eq(ProviderFactory::RepositoryType::Mercurial)
    end

    it "detects Fossil type" do
      ProviderFactory.detect_repository_type("https://example.com/repo.fossil").should eq(ProviderFactory::RepositoryType::Fossil)
    end
  end

  describe ".create" do
    it "creates GithubProvider for GitHub URLs" do
      provider = ProviderFactory.create("https://github.com/user/repo")
      provider.should be_a(GithubProvider)
      provider.provider_name.should eq("github")
      provider.repository_type.should eq("git")
    end

    it "creates GitlabProvider for GitLab URLs" do
      provider = ProviderFactory.create("https://gitlab.com/user/repo")
      provider.should be_a(GitlabProvider)
      provider.provider_name.should eq("gitlab")
      provider.repository_type.should eq("git")
    end

    it "creates BitbucketProvider for Bitbucket URLs" do
      provider = ProviderFactory.create("https://bitbucket.org/user/repo")
      provider.should be_a(BitbucketProvider)
      provider.provider_name.should eq("bitbucket")
      provider.repository_type.should eq("git")
    end

    it "creates CodebergProvider for Codeberg URLs" do
      provider = ProviderFactory.create("https://codeberg.org/user/repo")
      provider.should be_a(CodebergProvider)
      provider.provider_name.should eq("codeberg")
      provider.repository_type.should eq("git")
    end

    # Non-forge hosts no longer reach a provider through the factory. What still
    # matters is that classification picks the right provider for each kind of
    # repository, so that is asserted directly rather than through a create()
    # call the gate refuses.
    it "classifies self-hosted repositories without building a provider for them" do
      ProviderFactory.detect_provider_type("https://example.com/repo.git").should eq("git")
      ProviderFactory.detect_provider_type("https://example.com/repo.hg").should eq("mercurial")
      ProviderFactory.detect_provider_type("https://example.com/repo.fossil").should eq("fossil")
      ProviderFactory.detect_provider_type("https://example.com/fossil/repo").should eq("fossil")
    end

    it "names and types each provider it can build" do
      GenericGitProvider.new("https://example.com/repo.git").provider_name.should eq("generic_git")
      GenericGitProvider.new("https://example.com/repo.git").repository_type.should eq("git")
      MercurialProvider.new("https://example.com/repo.hg").provider_name.should eq("mercurial")
      MercurialProvider.new("https://example.com/repo.hg").repository_type.should eq("mercurial")
      FossilProvider.new("https://example.com/repo.fossil").provider_name.should eq("fossil")
      FossilProvider.new("https://example.com/repo.fossil").repository_type.should eq("fossil")
    end

    it "refuses to build anything for a host outside the allowlist" do
      expect_raises(GitHostPolicy::UnsafeUrlError) do
        ProviderFactory.create("https://example.com/repo.git")
      end
    end
  end
end
