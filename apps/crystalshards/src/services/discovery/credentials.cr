module Discovery
  # Raised when a host is asked to be crawled without the token that host needs.
  class MissingTokenError < Exception
  end

  # Host tokens are configuration. Whether a crawl without one fails closed
  # depends on the host, and the difference was measured rather than assumed.
  #
  # GitHub and Bitbucket genuinely require one. GitHub's code search API, the
  # only way to ask "which repositories have a shard.yml at their root",
  # answers an unauthenticated request with 401, and the rest of its API allows
  # 60 requests an hour, which a sweep exhausts inside the first page.
  # Bitbucket gives an anonymous caller 60 an hour and answers many workspace
  # enumerations with 403 whether or not they hold shards. A crawl that starts
  # anyway on either host produces a handful of shards and a `partial` row,
  # which reads like a host with almost no Crystal on it rather than like a
  # missing token.
  #
  # GitLab and Codeberg do not. Neither crawler uses the endpoint that would
  # need auth: GitLab's uses the topic scoped project listing precisely because
  # blob search 401s, and Codeberg's uses Forgejo's public repository search.
  # Both were checked against the live hosts with no credential at all: the
  # listing and the raw shard.yml fetch each answered 200, and the whole sweep
  # is around a hundred requests, far inside the anonymous allowances. Refusing
  # to crawl them without a token cost real coverage for no safety.
  #
  # So a token is optional on those two. It is still used when present, which
  # buys a higher rate limit and nothing else.
  module Credentials
    TOKEN_ENV = {
      "github.com"    => "GITHUB_TOKEN",
      "gitlab.com"    => "GITLAB_TOKEN",
      "codeberg.org"  => "CODEBERG_TOKEN",
      "bitbucket.org" => "BITBUCKET_APP_PASSWORD",
    }

    # The hosts whose public API a sweep can read anonymously. Everything else
    # in TOKEN_ENV fails closed without its credential.
    OPTIONAL_TOKEN_HOSTS = Set{"gitlab.com", "codeberg.org"}

    # Bitbucket is the one host whose credential is a pair. Its API takes an app
    # password over HTTP Basic, and Basic needs the account it belongs to, so
    # the secret alone is not enough to authenticate. The variable names are the
    # ones BitbucketProvider already reads, because a second spelling for the
    # same credential is how an operator ends up with a working fetch and a
    # refusing crawl.
    USERNAME_ENV = {
      "bitbucket.org" => "BITBUCKET_USERNAME",
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

    # The token a crawler must have. Only ever called for a host that requires
    # one; an optional token host reaches its crawler through `token_for?` and
    # a nil, which the crawlers already accept by omitting the auth header.
    def self.token_for(host : String) : String
      token_for?(host) || raise MissingTokenError.new(missing_message(host))
    end

    # Whether this host can be crawled at all right now.
    #
    # True for an optional token host whether or not a token is present, which
    # is the whole point: gitlab.com and codeberg.org answer the calls their
    # crawlers make without one.
    def self.crawlable?(host : String) : Bool
      return true if OPTIONAL_TOKEN_HOSTS.includes?(host)

      configured?(host)
    end

    # Whether a token is required before this host will answer.
    def self.token_required?(host : String) : Bool
      TOKEN_ENV.has_key?(host) && !OPTIONAL_TOKEN_HOSTS.includes?(host)
    end

    # The account an app password belongs to, for the one host that needs it.
    def self.username_for?(host : String) : String?
      variable = USERNAME_ENV[host]?
      return nil unless variable

      if table = @@source
        table[variable]?.presence
      else
        ENV[variable]?.presence
      end
    end

    # Configured means the host can actually authenticate, which for a host with
    # a credential pair means both halves. Treating the app password alone as
    # configured would start a sweep that 401s on its first request.
    #
    # Distinct from `crawlable?`: a host can be crawlable with no credential and
    # unconfigured at the same time, which is exactly the state gitlab.com and
    # codeberg.org are in by default.
    def self.configured?(host : String) : Bool
      return false if token_for?(host).nil?
      return true unless USERNAME_ENV.has_key?(host)

      !username_for?(host).nil?
    end

    def self.env_var_for(host : String) : String?
      TOKEN_ENV[host]?
    end

    def self.missing_message(host : String) : String
      variable = TOKEN_ENV[host]?
      return "#{host} is not a host this registry knows how to crawl" unless variable

      needed = if account = USERNAME_ENV[host]?
                 "set #{account} and #{variable} to an account and app password with public read scope"
               else
                 "set #{variable} to a token with public read scope"
               end

      "Refusing to crawl #{host} without a token: #{needed}. " \
      "An unauthenticated sweep of #{host} cannot complete (#{unauthenticated_limit(host)}), so it would " \
      "leave the registry looking like #{host} has almost no shards on it."
    end

    private def self.unauthenticated_limit(host : String) : String
      case host
      when "github.com"
        "code search requires authentication and returns 401, and the rest of the API allows 60 requests an hour"
      when "gitlab.com"
        "unauthenticated API requests are throttled to 500 per period and blob search returns 401"
      when "codeberg.org"
        "unauthenticated requests share a 2000 per 10 minutes baseline with every other anonymous caller"
      when "bitbucket.org"
        "anonymous callers get 60 requests an hour, measured live as " \
        "x-ratelimit-limit: 60, 60;w=3600, and many workspaces answer an anonymous " \
        "enumeration with 403 whether or not they hold shards"
      else
        "unauthenticated requests are rate limited"
      end
    end
  end
end
