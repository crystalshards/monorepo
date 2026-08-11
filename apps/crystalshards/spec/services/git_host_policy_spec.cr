require "../spec_helper"

# `repository_url` arrives from a submission or a crawler and is then handed to a
# provider that will clone or fetch it. That makes it a request originating inside
# our network with whatever the pod can reach, so these examples are about what
# the registry refuses to point itself at.
private def with_resolution(addresses : Array(String), &)
  GitHostPolicy.resolver = ->(_host : String) do
    addresses.map { |address| Socket::IPAddress.new(address, 443) }
  end
  begin
    yield
  ensure
    GitHostPolicy.resolver = nil
  end
end

private PUBLIC_GITHUB = ["140.82.121.4"]

describe GitHostPolicy do
  describe "addresses that must never be fetched" do
    it "refuses localhost" do
      GitHostPolicy.safe_fetch_url?("http://localhost/owner/repo").should be_false
    end

    it "refuses the loopback range" do
      GitHostPolicy.safe_fetch_url?("http://127.0.0.1/owner/repo").should be_false
      GitHostPolicy.safe_fetch_url?("http://127.0.0.53:8080/owner/repo").should be_false
      GitHostPolicy.safe_fetch_url?("http://[::1]/owner/repo").should be_false
    end

    it "refuses the RFC1918 private ranges" do
      [
        "http://10.0.0.5/owner/repo",
        "http://172.16.4.1/owner/repo",
        "http://172.31.255.254/owner/repo",
        "http://192.168.1.10/owner/repo",
      ].each do |url|
        GitHostPolicy.safe_fetch_url?(url).should be_false
      end
    end

    it "refuses the link-local range, which on GCP is the metadata server" do
      # This is the one that hands out credentials, so it gets its own example.
      GitHostPolicy.safe_fetch_url?("http://169.254.169.254/computeMetadata/v1/").should be_false

      message = expect_raises(GitHostPolicy::UnsafeUrlError) do
        GitHostPolicy.validate_fetch_url!("http://169.254.169.254/computeMetadata/v1/")
      end.message.to_s

      message.should contain("169.254.169.254")
      message.should contain("non-public")
    end

    it "refuses the metadata server reached through IPv6 spellings" do
      # An IPv4-mapped or NAT64 address is the same destination written
      # differently, and a v4-only range check never sees it.
      GitHostPolicy.safe_fetch_url?("http://[::ffff:169.254.169.254]/latest/meta-data/").should be_false
      GitHostPolicy.safe_fetch_url?("http://[64:ff9b::a9fe:a9fe]/latest/meta-data/").should be_false
    end

    it "refuses IPv6 loopback, link-local and unique-local addresses" do
      [
        "http://[::]/owner/repo",
        "http://[fe80::1]/owner/repo",
        "http://[fd00::1]/owner/repo",
        "http://[fc00::1]/owner/repo",
      ].each do |url|
        GitHostPolicy.safe_fetch_url?(url).should be_false
      end
    end

    it "refuses an obfuscated loopback literal" do
      # 2130706433 is 127.0.0.1 in decimal, and 0177.0.0.1 is octal. Neither is a
      # hostname the registry knows, which is what refuses them.
      GitHostPolicy.safe_fetch_url?("http://2130706433/owner/repo").should be_false
      GitHostPolicy.safe_fetch_url?("http://0177.0.0.1/owner/repo").should be_false
    end
  end

  describe "a hostname that resolves to a private address" do
    it "is refused even though the host is on the allowlist" do
      # The whole point of resolving: a string check sees "github.com" and waves
      # it through, whatever DNS actually answers.
      with_resolution(["10.0.0.7"]) do
        GitHostPolicy.safe_fetch_url?("https://github.com/owner/repo").should be_false
      end
    end

    it "is refused when only one of several answers is private" do
      with_resolution(["140.82.121.4", "169.254.169.254"]) do
        message = expect_raises(GitHostPolicy::UnsafeUrlError) do
          GitHostPolicy.validate_fetch_url!("https://github.com/owner/repo")
        end.message.to_s

        message.should contain("169.254.169.254")
      end
    end

    it "is refused when the name does not resolve at all" do
      # Fail closed: an address we could not check is not an address we trust.
      with_resolution([] of String) do
        GitHostPolicy.safe_fetch_url?("https://github.com/owner/repo").should be_false
      end
    end

    it "is refused, not raised through, when resolution itself fails" do
      # SaveShard calls safe_fetch_url? on every write, so a machine with no DNS
      # must produce a refusal rather than an exception escaping into the
      # operation and failing every shard save with a stack trace.
      #
      # Socket::Addrinfo::Error, which a real failed lookup raises, is a
      # Socket::Error, and Socket::Error is what the policy rescues.
      GitHostPolicy.resolver = ->(_host : String) do
        raise Socket::Error.new("no address associated with hostname")
        [] of Socket::IPAddress
      end

      begin
        GitHostPolicy.safe_fetch_url?("https://github.com/owner/repo").should be_false

        expect_raises(GitHostPolicy::UnsafeUrlError, /could not resolve github\.com/) do
          GitHostPolicy.validate_fetch_url!("https://github.com/owner/repo")
        end
      ensure
        GitHostPolicy.resolver = nil
      end
    end
  end

  describe "URLs that are refused on their face" do
    it "refuses embedded credentials" do
      with_resolution(PUBLIC_GITHUB) do
        GitHostPolicy.safe_fetch_url?("https://user:token@github.com/owner/repo").should be_false
      end
    end

    it "refuses schemes that are not http or https" do
      ["file:///etc/passwd", "gopher://github.com/owner/repo", "ftp://github.com/o/r"].each do |url|
        GitHostPolicy.safe_fetch_url?(url).should be_false
      end
    end

    it "refuses hosts that merely look like an allowlisted host" do
      # Both of these satisfy a naive includes?/ends_with? check.
      with_resolution(PUBLIC_GITHUB) do
        GitHostPolicy.safe_fetch_url?("https://github.com.evil.test/owner/repo").should be_false
        GitHostPolicy.safe_fetch_url?("https://evilgithub.com/owner/repo").should be_false
      end
    end

    it "refuses self-hosted git, since discovery cannot crawl it and fetching it is the hole" do
      with_resolution(["93.184.216.34"]) do
        GitHostPolicy.safe_fetch_url?("https://git.example.test/owner/repo.git").should be_false
      end
    end
  end

  describe "the hosts the registry does fetch from" do
    it "accepts them when they resolve to a public address" do
      with_resolution(PUBLIC_GITHUB) do
        %w[
          https://github.com/kemalcr/kemal
          https://gitlab.com/owner/repo
          https://bitbucket.org/owner/repo
          https://codeberg.org/owner/repo
        ].each do |url|
          GitHostPolicy.safe_fetch_url?(url).should be_true
        end
      end
    end

    it "accepts a www prefix and a trailing dot on the hostname" do
      with_resolution(PUBLIC_GITHUB) do
        GitHostPolicy.safe_fetch_url?("https://www.github.com/owner/repo").should be_true
        GitHostPolicy.safe_fetch_url?("https://github.com./owner/repo").should be_true
      end
    end

    it "rewrites scp-style remotes to https rather than refusing them" do
      GitHostPolicy.normalize_url("git@github.com:kemalcr/kemal.git")
        .should eq("https://github.com/kemalcr/kemal.git")

      with_resolution(PUBLIC_GITHUB) do
        GitHostPolicy.safe_fetch_url?("git@github.com:kemalcr/kemal.git").should be_true
      end
    end

    it "leaves an scp-style remote for an unknown host alone, so it is refused" do
      GitHostPolicy.normalize_url("git@git.example.test:owner/repo.git")
        .should eq("git@git.example.test:owner/repo.git")
      GitHostPolicy.safe_fetch_url?("git@git.example.test:owner/repo.git").should be_false
    end
  end

  describe "the gate in front of provider creation" do
    it "refuses to build a provider for the metadata server" do
      expect_raises(GitHostPolicy::UnsafeUrlError) do
        ProviderFactory.create("http://169.254.169.254/latest/meta-data/")
      end
    end

    it "refuses to build a provider for a private address" do
      expect_raises(GitHostPolicy::UnsafeUrlError) do
        ProviderFactory.create("http://192.168.0.42/owner/repo.git")
      end
    end

    it "refuses to build a provider for a self-hosted host" do
      expect_raises(GitHostPolicy::UnsafeUrlError) do
        ProviderFactory.create("https://git.example.test/owner/repo.git")
      end
    end

    it "still builds providers for the hosts we support" do
      with_resolution(PUBLIC_GITHUB) do
        ProviderFactory.create("https://github.com/owner/repo").should be_a(GithubProvider)
        ProviderFactory.create("https://gitlab.com/owner/repo").should be_a(GitlabProvider)
        ProviderFactory.create("https://bitbucket.org/owner/repo").should be_a(BitbucketProvider)
        ProviderFactory.create("https://codeberg.org/owner/repo").should be_a(CodebergProvider)
      end
    end

    it "classifies without opening a socket" do
      # detect_provider_type used to run `git ls-remote` against the URL through a
      # shell. If that ever comes back, this example hangs or fails instead of
      # quietly making an outbound request for every classification.
      ProviderFactory.detect_provider_type("https://git.example.test/owner/repo").should eq("git")
      ProviderFactory.detect_provider_type("https://github.com/owner/repo").should eq("github")
      ProviderFactory.detect_repository_type("https://git.example.test/repo.hg")
        .should eq(ProviderFactory::RepositoryType::Mercurial)
    end
  end

  describe "a clone that bypassed the factory" do
    it "is still refused, because the check is at the fetch too" do
      # A provider can be constructed directly, so the gate cannot live only in
      # ProviderFactory.create.
      provider = GenericGitProvider.new("http://169.254.169.254/latest/meta-data/")
      provider.clone_repository(File.tempname("discovery_spec")).should be_false
    end

    it "refuses a ref that would be read as a git option" do
      # The ref reaches git as an argument, so it cannot inject a command, but
      # "--upload-pack=..." is still git doing something we did not ask for.
      provider = GenericGitProvider.new("https://github.com/owner/repo")
      provider.checkout_version(Dir.tempdir, "--upload-pack=touch /tmp/pwned").should be_false
      provider.checkout_version(Dir.tempdir, "../../etc").should be_false
    end
  end
end
