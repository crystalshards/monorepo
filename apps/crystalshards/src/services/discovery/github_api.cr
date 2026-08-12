require "base64"

module Discovery
  # The parts of GitHub's API that are the same whichever way a crawler
  # enumerates the host: where the API lives, how a token is presented, and how
  # to ask whether a repository has a shard.yml at its root.
  #
  # Two crawlers enumerate github.com and they disagree about nothing except the
  # search endpoint. GithubCrawler partitions code search by file size and is
  # exhaustive; HighValueCrawler reads repository search ranked by stars and is
  # deliberately only the top of it. Sharing this module is what keeps the
  # authoritative "is it a shard" check identical between them, which matters
  # because the two paths meet on the same rows.
  module GithubApi
    API_ROOT = "https://api.github.com"

    def default_base_url : String
      API_ROOT
    end

    def auth_headers(token : String?) : HTTP::Headers
      headers = HTTP::Headers{
        "Accept"               => "application/vnd.github+json",
        "X-GitHub-Api-Version" => "2022-11-28",
      }
      headers["Authorization"] = "Bearer #{token}" if token
      headers
    end

    # The authoritative check, and the only one either crawler trusts.
    #
    # Search told us something about this repository: that a file matched, or
    # that it is written in Crystal, or that somebody tagged it. None of that is
    # "there is a shard.yml at the root", and repository search in particular
    # returns applications, dotfiles and awesome-lists that are not shards at
    # all. The contents endpoint is the answer, and it carries the manifest,
    # which is where the shard's name comes from.
    #
    # nil means "not a shard" and must mean only that: a transport failure has
    # to raise, or a rate-limited sweep would file every repository it could not
    # read as a repository without a manifest.
    def fetch_shard_yml(repository : DiscoveredRepository) : String?
      path = "/repos/#{repository.owner}/#{repository.repo}/contents/shard.yml"
      payload = client.get_json(path)

      return nil unless payload["type"]?.try(&.as_s?) == "file"

      encoded = payload["content"]?.try(&.as_s?)
      return nil unless encoded

      String.new(Base64.decode(encoded.gsub(/\s/, "")))
    rescue HostClient::NotFound
      nil
    rescue ex : Base64::Error
      Log.info { "#{repository.slug} shard.yml did not decode: #{ex.message}" }
      nil
    end
  end
end
