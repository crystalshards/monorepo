require "../services/git_host_policy"
require "./base_provider"
require "./github_provider"
require "./gitlab_provider"
require "./bitbucket_provider"
require "./codeberg_provider"
require "./generic_git_provider"
require "./mercurial_provider"
require "./fossil_provider"

class ProviderFactory
  enum RepositoryType
    Git
    Mercurial
    Fossil
  end

  class UnsupportedProviderError < Exception
  end

  # Test seam. When set, `create` delegates to this proc instead of sniffing
  # the repository URL, which lets specs hand a worker a provider that never
  # touches the network. Always nil in production.
  class_property builder : Proc(String, BaseProvider)? = nil

  # Every real provider in the registry is built here, so this is where the URL
  # gate belongs. Raises GitHostPolicy::UnsafeUrlError for anything that is not
  # a known public git host, which is what stops a submitted repository_url
  # from becoming a request against our own network.
  #
  # The builder seam is checked first and deliberately ungated: it exists so
  # specs can hand a worker a provider that never opens a socket, and a mock
  # provider has no network to protect. Production leaves it nil.
  def self.create(repository_url : String) : BaseProvider
    if custom = @@builder
      return custom.call(repository_url)
    end

    url = GitHostPolicy.normalize_url(repository_url)
    GitHostPolicy.validate_fetch_url!(url)
    detect_and_create(url)
  end

  # Pure string classification. This used to shell out to `git ls-remote` and
  # `hg identify` against the URL to decide, which made classification alone an
  # outbound request with the URL interpolated into a shell command. Detection
  # now never touches the network.
  def self.detect_provider_type(repository_url : String) : String
    case repository_url
    when /github\.com/
      "github"
    when /gitlab\.com/
      "gitlab"
    when /bitbucket\.org/
      "bitbucket"
    when /codeberg\.org/
      "codeberg"
    when /\.hg$/
      "mercurial"
    when /\.fossil$/, /\/fossil\//
      "fossil"
    else
      "git"
    end
  end

  def self.detect_repository_type(repository_url : String) : RepositoryType
    case detect_provider_type(repository_url)
    when "mercurial"
      RepositoryType::Mercurial
    when "fossil"
      RepositoryType::Fossil
    else
      RepositoryType::Git
    end
  end

  private def self.detect_and_create(repository_url : String) : BaseProvider
    provider_type = detect_provider_type(repository_url)

    case provider_type
    when "github"
      GithubProvider.new(repository_url)
    when "gitlab"
      GitlabProvider.new(repository_url)
    when "bitbucket"
      BitbucketProvider.new(repository_url)
    when "codeberg"
      CodebergProvider.new(repository_url)
    when "git"
      GenericGitProvider.new(repository_url)
    when "mercurial"
      MercurialProvider.new(repository_url)
    when "fossil"
      FossilProvider.new(repository_url)
    else
      GenericGitProvider.new(repository_url)
    end
  end
end
