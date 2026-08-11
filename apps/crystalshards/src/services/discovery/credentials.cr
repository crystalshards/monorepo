module Discovery
  # Raised when a host is asked to be crawled without the token that host needs.
  class MissingTokenError < Exception
  end

  # Host tokens are configuration, and a crawl without one fails closed.
  #
  # This is not caution for its own sake. GitHub's code search API, which is the
  # only way to ask "which repositories have a shard.yml at their root", answers
  # an unauthenticated request with 401 Requires authentication. Its other APIs
  # allow 60 requests an hour unauthenticated, which a sweep exhausts inside the
  # first page and then spends the rest of the run backing off. A crawl that
  # starts anyway produces a handful of shards and a `partial` row, which reads
  # like a host with almost no Crystal on it rather than like a missing token.
  module Credentials
    TOKEN_ENV = {
      "github.com"   => "GITHUB_TOKEN",
      "gitlab.com"   => "GITLAB_TOKEN",
      "codeberg.org" => "CODEBERG_TOKEN",
    }

    # Test seam. When set, lookups read this table of environment variable name
    # to token instead of the process environment, so specs can exercise both
    # the configured and the missing token path without mutating ENV for every
    # other spec in the run. An empty hash means "no tokens anywhere", which is
    # not the same as nil, which means "read the real environment".
    #
    # A table rather than a proc on purpose: a nilable Proc class variable is a
    # standing fight with Crystal's inference, which narrows the return type at
    # the assignment and then rejects it against the declaration.
    @@source : Hash(String, String)? = nil

    def self.source : Hash(String, String)?
      @@source
    end

    def self.source=(tokens : Hash(String, String)?)
      @@source = tokens
    end

    def self.token_for?(host : String) : String?
      variable = TOKEN_ENV[host]?
      return nil unless variable

      if table = @@source
        table[variable]?.presence
      else
        ENV[variable]?.presence
      end
    end

    def self.token_for(host : String) : String
      token_for?(host) || raise MissingTokenError.new(missing_message(host))
    end

    def self.configured?(host : String) : Bool
      !token_for?(host).nil?
    end

    def self.env_var_for(host : String) : String?
      TOKEN_ENV[host]?
    end

    def self.missing_message(host : String) : String
      if variable = TOKEN_ENV[host]?
        "Refusing to crawl #{host} without a token: set #{variable} to a token with public read scope. " \
        "An unauthenticated sweep of #{host} cannot complete (#{unauthenticated_limit(host)}), so it would " \
        "leave the registry looking like #{host} has almost no shards on it."
      else
        "#{host} is not a host this registry knows how to crawl"
      end
    end

    private def self.unauthenticated_limit(host : String) : String
      case host
      when "github.com"
        "code search requires authentication and returns 401, and the rest of the API allows 60 requests an hour"
      when "gitlab.com"
        "unauthenticated API requests are throttled to 500 per period and blob search returns 401"
      when "codeberg.org"
        "unauthenticated requests share a 2000 per 10 minutes baseline with every other anonymous caller"
      else
        "unauthenticated requests are rate limited"
      end
    end
  end
end
