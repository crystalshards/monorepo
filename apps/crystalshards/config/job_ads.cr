require "uri"

module CrystalShards
  # Where the job ad strip gets its jobs.
  #
  # There is deliberately no default URL. A baked-in CrystalGigs host would be a
  # deployment fact living in source, and the first time anyone forgot to set
  # the variable it would quietly point a laptop, a CI runner or a staging box
  # at production.
  #
  # Production refuses to boot without it. The failure that prevents is the
  # expensive one: an ad strip that silently never renders, on three sites, with
  # nothing in the logs to say why, because "no ad" is also what a healthy
  # empty board looks like. Everywhere else an unset value turns the strip off
  # and says so once at boot, rather than leaving someone to infer it from a
  # page that looks fine.
  module JobAdsConfig
    ENV_KEY = "JOB_ADS_URL"

    class MissingEndpoint < Exception
      def initialize
        super(<<-MESSAGE)
        #{ENV_KEY} is not set.

        The job ad strip reads promotable jobs from CrystalGigs, and production
        will not start without knowing where that is. Set it to the ads feed,
        for example:

          #{ENV_KEY}=https://<crystalgigs-host>/api/ads

        In development and test, leaving it unset is allowed and turns the ad
        strip off.
        MESSAGE
      end
    end

    class InvalidEndpoint < Exception
      def initialize(raw : String)
        super("#{ENV_KEY} is not an absolute http(s) URL: #{raw.inspect}")
      end
    end

    # nil means the strip is off. Callers never have to ask why.
    #
    # Writable so a spec can point the strip at a stub or switch it off
    # without reaching into the process environment. The value that matters,
    # the one production boots with, still comes from resolve_endpoint below.
    class_property endpoint : URI? = resolve_endpoint

    def self.enabled? : Bool
      !@@endpoint.nil?
    end

    private def self.resolve_endpoint : URI?
      raw = ENV[ENV_KEY]?

      if raw.nil? || raw.blank?
        raise MissingEndpoint.new if LuckyEnv.production?

        Log.for("job_ads").info { "#{ENV_KEY} unset, job ad strip disabled" }
        return nil
      end

      uri = URI.parse(raw)
      # A relative or scheme-less value parses without complaint and then fails
      # at request time on every page, so it is rejected here where the message
      # can name the variable.
      raise InvalidEndpoint.new(raw) unless uri.absolute? && {"http", "https"}.includes?(uri.scheme)

      uri
    rescue URI::Error
      raise InvalidEndpoint.new(raw.to_s)
    end
  end
end
