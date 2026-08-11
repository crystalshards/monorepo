module CrystalGigs
  # Configuration for ATS integrations.
  #
  # Two kinds of value are involved and they are deliberately stored in
  # different places:
  #
  # * A *board token* is public. It appears in the employer's own job board URL
  #   (`https://job-boards.greenhouse.io/<token>`, `https://jobs.lever.co/<token>`)
  #   and the inbound endpoints are unauthenticated, so it lives on the
  #   `AtsConnection` record as ordinary data.
  # * An *API key* is a secret used only for outbound application submission.
  #   It is read from the environment, never defaulted, never persisted, and
  #   never echoed back in a response.
  #
  # Nothing here has a fallback value. Asking for a credential that is not set
  # raises `MissingCredential` with the exact variable to set.
  class AtsConfig
    # Provider key => environment variable holding that provider's API key.
    CREDENTIAL_ENV_KEYS = {
      "greenhouse" => "ATS_GREENHOUSE_API_KEY",
      "lever"      => "ATS_LEVER_API_KEY",
    }

    # Envelope sender used when an application is handed off by email. There is
    # no default: an unset value disables the email link of the fallback chain
    # rather than inventing an address the employer never authorised.
    FROM_ADDRESS_ENV_KEY = "ATS_APPLICATION_FROM_EMAIL"

    class UnknownProvider < Exception
      def initialize(provider : String)
        super(
          "Unknown ATS provider '#{provider}'. " \
          "Providers with configurable credentials: #{CREDENTIAL_ENV_KEYS.keys.sort.join(", ")}."
        )
      end
    end

    class MissingCredential < Exception
      getter provider : String
      getter env_key : String

      def initialize(@provider : String, @env_key : String)
        super(
          "Missing ATS credential for '#{@provider}'. " \
          "Set the #{@env_key} environment variable to the provider API key. " \
          "There is no default and no placeholder."
        )
      end
    end

    class MissingFromAddress < Exception
      def initialize
        super(
          "Missing application handoff sender address. " \
          "Set the #{FROM_ADDRESS_ENV_KEY} environment variable to the address " \
          "applications should be sent from. There is no default."
        )
      end
    end

    def self.env_key_for(provider : String) : String
      CREDENTIAL_ENV_KEYS[provider.downcase]? || raise UnknownProvider.new(provider)
    end

    # The configured API key, or nil when the variable is unset or blank.
    def self.api_key?(provider : String) : String?
      value = ENV[env_key_for(provider)]?
      return nil if value.nil? || value.blank?
      value
    end

    # The configured API key. Fails closed with the variable name to set.
    def self.api_key(provider : String) : String
      api_key?(provider) || raise MissingCredential.new(provider.downcase, env_key_for(provider))
    end

    def self.credential_configured?(provider : String) : Bool
      !api_key?(provider).nil?
    rescue UnknownProvider
      false
    end

    def self.from_address? : String?
      value = ENV[FROM_ADDRESS_ENV_KEY]?
      return nil if value.nil? || value.blank?
      value
    end

    def self.from_address : String
      from_address? || raise MissingFromAddress.new
    end
  end
end
