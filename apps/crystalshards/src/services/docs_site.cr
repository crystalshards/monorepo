module CrystalShards
  # Where a shard's documentation lives on crystaldocs.
  #
  # The counterpart of `CrystalDocs::PackagePaths`, and it has to stay the
  # counterpart: this app decides the key a build is requested and stored
  # under, and crystaldocs decides the URL that reads it. Both are the same
  # key, so both spell it the same way. `CrystalStorage::Keys` is already
  # mirrored between the two apps for the same reason.
  #
  # A package is addressed by a host qualified key ("github.com/kemalcr/kemal")
  # whenever it has one, because a shard name is not unique and two "lsp"
  # shards addressed by name would read and write the same documentation. A
  # bare name is only for what predates that.
  module DocsSite
    ENV_KEY = "DOCS_SITE_ORIGIN"

    # Where crystaldocs answers. Required in every environment, with no default
    # and no production fallback.
    #
    # It was `https://crystaldocs.org`, written into the source. That is not a
    # constant, it is one deployment's address: locally crystaldocs is on
    # another port, and a hardcoded production URL meant every docs link on a
    # development machine pointed at production. It was also invisible, because
    # the value that made production work was the same value that made local
    # wrong, so nothing ever failed to reveal it.
    #
    # Raising rather than defaulting is the point. A default here is a guess
    # about where another service lives, and a wrong guess produces links that
    # resolve somewhere real, which is the failure nobody notices.
    class MissingOrigin < Exception
      def initialize
        super(
          "#{ENV_KEY} is not set. It is the origin crystaldocs answers on, " \
          "for example https://crystaldocs.org in production or " \
          "http://localhost:3001 against the local stack. Every documentation " \
          "link this app renders is built from it, so there is no value that " \
          "could be guessed that would not be wrong somewhere."
        )
      end
    end

    def self.origin : String
      raw = ENV[ENV_KEY]?
      raise MissingOrigin.new if raw.nil? || raw.blank?

      raw.rstrip('/')
    end

    # Repository keys are nested under a static segment so they cannot be
    # mistaken for a bare package name by the routes that still take one. The
    # reasoning lives with the routes, in `CrystalDocs::PackagePaths`.
    CANONICAL_SEGMENT = "_"

    def self.path_for(key : String, version : String? = nil) : String
      base =
        if key.includes?('/')
          "/docs/#{CANONICAL_SEGMENT}/#{key}"
        else
          "/docs/#{key}"
        end

      version ? "#{base}/#{version}" : base
    end

    def self.url_for(key : String, version : String? = nil) : String
      "#{origin}#{path_for(key, version)}"
    end

    # The documentation URL for a shard, or nil when it has no identity to
    # address one by.
    #
    # No version: crystaldocs holds the release list and picks the current one,
    # so a link written here cannot go stale the next time a maintainer tags.
    #
    # Nil for a row the backfill could not parse into host, owner and repo.
    # There is no key for it, so there is nothing to link to, and inventing one
    # from its name would point at whichever repository happened to claim that
    # name. `Shard#identity_error` is what the page shows instead.
    def self.url_for?(shard : Shard) : String?
      slug = shard.canonical_slug
      return nil unless slug

      url_for(slug)
    end
  end
end
