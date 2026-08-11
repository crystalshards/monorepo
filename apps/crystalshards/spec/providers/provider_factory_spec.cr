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

    # These used to assert that any URL produced a provider. They now assert the
    # opposite, which is the point of the gate: a repository_url the registry
    # will clone is a URL it can be made to fetch, so it is restricted to hosts
    # we know. Provider classification itself is tested below the gate, in
    # .detect_provider_type.
    it "refuses a self-hosted git URL rather than cloning whatever it is handed" do
      expect_raises(GitHostPolicy::UnsafeUrlError) do
        ProviderFactory.create("https://example.com/repo.git")
      end
    end

    it "refuses self-hosted Mercurial and Fossil URLs for the same reason" do
      expect_raises(GitHostPolicy::UnsafeUrlError) do
        ProviderFactory.create("https://example.com/repo.hg")
      end

      expect_raises(GitHostPolicy::UnsafeUrlError) do
        ProviderFactory.create("https://example.com/repo.fossil")
      end

      expect_raises(GitHostPolicy::UnsafeUrlError) do
        ProviderFactory.create("https://example.com/fossil/repo")
      end
    end

    it "refuses an address inside our own network" do
      expect_raises(GitHostPolicy::UnsafeUrlError) do
        ProviderFactory.create("http://169.254.169.254/latest/meta-data/")
      end
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
