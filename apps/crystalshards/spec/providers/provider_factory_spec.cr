require "../spec_helper"

describe ProviderFactory do
  describe ".create" do
    it "creates GithubProvider for GitHub URLs" do
      provider = ProviderFactory.create("https://github.com/user/repo")
      provider.should be_a(GithubProvider)
    end

    it "creates GithubProvider for GitHub SSH URLs" do
      provider = ProviderFactory.create("git@github.com:user/repo.git")
      provider.should be_a(GithubProvider)
    end

    it "creates GitlabProvider for GitLab URLs" do
      provider = ProviderFactory.create("https://gitlab.com/user/repo")
      provider.should be_a(GitlabProvider)
    end

    it "creates GitlabProvider for GitLab SSH URLs" do
      provider = ProviderFactory.create("git@gitlab.com:user/repo.git")
      provider.should be_a(GitlabProvider)
    end

    it "creates BitbucketProvider for Bitbucket URLs" do
      provider = ProviderFactory.create("https://bitbucket.org/user/repo")
      provider.should be_a(BitbucketProvider)
    end

    it "creates CodebergProvider for Codeberg URLs" do
      provider = ProviderFactory.create("https://codeberg.org/user/repo")
      provider.should be_a(CodebergProvider)
    end

    it "creates GenericGitProvider for generic Git URLs" do
      provider = ProviderFactory.create("https://example.com/repo.git")
      provider.should be_a(GenericGitProvider)
    end

    it "creates MercurialProvider for Mercurial URLs" do
      provider = ProviderFactory.create("https://example.com/repo.hg")
      provider.should be_a(MercurialProvider)
    end

    it "creates FossilProvider for Fossil URLs" do
      provider = ProviderFactory.create("https://example.com/repo.fossil")
      provider.should be_a(FossilProvider)
    end

    it "creates FossilProvider for Fossil-specific URLs" do
      provider = ProviderFactory.create("https://example.com/fossil/repo")
      provider.should be_a(FossilProvider)
    end
  end

  describe ".detect_provider_type" do
    it "detects github" do
      ProviderFactory.detect_provider_type("https://github.com/user/repo").should eq("github")
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
    it "detects Git type" do
      ProviderFactory.detect_repository_type("https://github.com/user/repo").should eq(ProviderFactory::RepositoryType::Git)
    end

    it "detects Mercurial type" do
      ProviderFactory.detect_repository_type("https://example.com/repo.hg").should eq(ProviderFactory::RepositoryType::Mercurial)
    end

    it "detects Fossil type" do
      ProviderFactory.detect_repository_type("https://example.com/repo.fossil").should eq(ProviderFactory::RepositoryType::Fossil)
    end
  end
end
