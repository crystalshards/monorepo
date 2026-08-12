require "./github_repository_api"
require "./host_repository_sources"

# Which source reads which host.
#
# Credentials are read through Discovery::Credentials rather than from ENV
# directly, so indexing authenticates with exactly the variables the crawler
# already documents and a spec can swap the whole table at once. A second
# spelling for the same credential is how an operator ends up with a working
# crawl and a silently anonymous indexer.
module RepositorySourceFactory
  # Hosts with a source. Deliberately the same list the crawler enumerates, so
  # anything discovery can find, indexing can read.
  HOSTS = ["github.com", "gitlab.com", "codeberg.org", "bitbucket.org"]

  # Test seam. Specs install a builder returning a source driven from fixtures,
  # so the indexer runs with no network, and must restore it in an `ensure`.
  class_property builder : Proc(String, String, RepositorySource?)? = nil

  class UnsupportedHostError < Exception
  end

  def self.for(host : String, repo_path : String) : RepositorySource
    if builder = @@builder
      if source = builder.call(host, repo_path)
        return source
      end
    end

    token = Discovery::Credentials.token_for?(host)

    case host
    when "github.com"    then GithubRepositoryApi.new(repo_path, token: token)
    when "gitlab.com"    then GitlabRepositorySource.new(repo_path, token: token)
    when "codeberg.org"  then CodebergRepositorySource.new(repo_path, token: token)
    when "bitbucket.org" then BitbucketRepositorySource.new(repo_path, token: token)
    else
      raise UnsupportedHostError.new(
        "#{host} is not a host the registry can read. Shards reach the registry from " \
        "#{HOSTS.join(", ")}; anything else is submitted and never indexed."
      )
    end
  end

  def self.supports?(host : String?) : Bool
    !host.nil? && HOSTS.includes?(host)
  end
end
