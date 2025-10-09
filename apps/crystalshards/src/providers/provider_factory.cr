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

  def self.create(repository_url : String) : BaseProvider
    detect_and_create(repository_url)
  end

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
    when /\.git$/
      "git"
    when /\.hg$/
      "mercurial"
    when /\.fossil$/
      "fossil"
    else
      if git_repository?(repository_url)
        "git"
      elsif mercurial_repository?(repository_url)
        "mercurial"
      elsif fossil_repository?(repository_url)
        "fossil"
      else
        "git"
      end
    end
  end

  def self.detect_repository_type(repository_url : String) : RepositoryType
    case repository_url
    when /\.hg$/
      RepositoryType::Mercurial
    when /\.fossil$/
      RepositoryType::Fossil
    else
      if mercurial_repository?(repository_url)
        RepositoryType::Mercurial
      elsif fossil_repository?(repository_url)
        RepositoryType::Fossil
      else
        RepositoryType::Git
      end
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

  private def self.git_repository?(url : String) : Bool
    return false if url.empty?

    test_cmd = "git ls-remote --exit-code -h #{url} 2>/dev/null"
    system(test_cmd)
  end

  private def self.mercurial_repository?(url : String) : Bool
    return false if url.empty?

    test_cmd = "hg identify #{url} 2>/dev/null"
    system(test_cmd)
  end

  private def self.fossil_repository?(url : String) : Bool
    return false if url.empty?

    url.ends_with?(".fossil") || url.includes?("/fossil/")
  end
end
