require "uri"

module CrystalShards
  # Where crystalgigs.com answers, for the ad strip's first-party house ads.
  #
  # Read the same way CrystalShards::DocsSite reads DOCS_SITE_ORIGIN: a
  # scheme and host with no path, because a doubled scheme or a trailing
  # fragment produces a link that looks clickable and resolves nowhere real,
  # which is exactly the incident DocsSite's own validation exists to catch
  # (see its MalformedOrigin comment).
  #
  # There is deliberately no default URL, for the same reason JobAdsConfig
  # has none: a baked-in CrystalGigs host would be a deployment fact living
  # in source, and the first time anyone forgot to set the variable it would
  # quietly point a laptop, a CI runner or a staging box at production.
  #
  # Production refuses to boot without it. Everywhere else an unset value
  # turns the house-ad fallback off and says so once at boot, rather than
  # leaving someone to infer it from a page that looks fine.
  module GigsSiteConfig
    ENV_KEY = "GIGS_SITE_ORIGIN"

    class MissingOrigin < Exception
      def initialize
        super(<<-MESSAGE)
        #{ENV_KEY} is not set.

        The ad strip's house ads link to crystalgigs.com, and production will
        not start without knowing where that is. Set it to the site's origin,
        for example:

          #{ENV_KEY}=https://crystalgigs.com

        In development and test, leaving it unset is allowed and turns house
        ads off.
        MESSAGE
      end
    end

    class MalformedOrigin < Exception
      def initialize(raw : String, reason : String)
        super(
          "#{ENV_KEY} is #{raw.inspect}, which #{reason}. It must be a " \
          "scheme and host with no path, for example https://crystalgigs.com."
        )
      end
    end

    # nil means house ads are off. Callers never have to ask why.
    #
    # Writable so a spec can point the fallback at a stub origin or switch it
    # off without reaching into the process environment. The value that
    # matters, the one production boots with, still comes from
    # resolve_origin below.
    class_property origin : String? = resolve_origin

    def self.enabled? : Bool
      !@@origin.nil?
    end

    private def self.resolve_origin : String?
      raw = ENV[ENV_KEY]?

      if raw.nil? || raw.blank?
        raise MissingOrigin.new if LuckyEnv.production?

        Log.for("gigs_site").info { "#{ENV_KEY} unset, house ads disabled" }
        return nil
      end

      value = raw.strip.rstrip('/')
      uri = URI.parse(value)

      raise MalformedOrigin.new(value, "has no scheme") if uri.scheme.nil?
      unless {"http", "https"}.includes?(uri.scheme)
        raise MalformedOrigin.new(value, "is not http or https")
      end
      # A doubled scheme parses with the second one as the path, which is how
      # DOCS_SITE_ORIGIN once reached production looking valid but broken.
      raise MalformedOrigin.new(value, "has no host") if uri.host.nil? || uri.host.try(&.blank?)
      raise MalformedOrigin.new(value, "has a path") unless uri.path.blank?

      value
    end
  end
end
