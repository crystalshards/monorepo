require "http/client"
require "json"

module CrystalBits
  # The ambient Cloud Run identity, read from the instance metadata server.
  #
  # Nothing here is a credential in source. The metadata server is only
  # reachable from inside a Google-managed instance and answers with the
  # identity the deployment already assigned to this revision, so there is no
  # key to leak, rotate or accidentally commit. That is the whole reason the
  # Search Console fetch does not take a service account key: there is not
  # one to take.
  #
  # Not reachable in development or test, and never called there: specs stub
  # the identity seam on SearchConsole, and development leaves the feature
  # unconfigured.
  module GoogleMetadata
    HOST = "metadata.google.internal"

    # Metadata requests without this header are refused, which is what stops a
    # server-side request forgery in an app from reading the instance's tokens.
    HEADERS = HTTP::Headers{"Metadata-Flavor" => "Google"}

    class Unavailable < Exception
      def initialize(path : String, detail : String)
        super("Could not read #{path} from the metadata server: #{detail}. This process expects to run on Cloud Run.")
      end
    end

    # Explicitly typed: an unannotated `@@ivar ||=` cannot be inferred.
    @@service_account_email : String?

    # The email of the service account this revision runs as. A Search
    # Console 403 names this account, because it is the address a human has
    # to add to the property before any data exists.
    def self.service_account_email : String
      @@service_account_email ||= get("/computeMetadata/v1/instance/service-accounts/default/email")
    end

    # A short-lived OAuth token for calling Google APIs as this revision.
    #
    # `scopes` narrows the token to the APIs that need something other than
    # the runtime default. Cloud Run mints a cloud-platform token when none
    # is asked for, and cloud-platform does not cover every Google API:
    # Search Console rejects it with "Request had insufficient authentication
    # scopes", which is a 403 that looks exactly like a missing grant and is
    # not one. Callers that need a specific scope name it.
    #
    # Deliberately not cached. The metadata server already caches and
    # refreshes underneath, and caching the string here would mean holding an
    # expiring credential in process memory for longer than it is valid.
    def self.access_token(scopes : String? = nil) : String
      path = "/computeMetadata/v1/instance/service-accounts/default/token"
      path += "?scopes=#{URI.encode_www_form(scopes)}" if scopes
      body = get(path)

      JSON.parse(body)["access_token"].as_s
    rescue ex : JSON::Error | KeyError
      raise Unavailable.new("the access token", ex.message.to_s)
    end

    private def self.get(path : String) : String
      response = HTTP::Client.get("http://#{HOST}#{path}", headers: HEADERS)

      unless response.success?
        raise Unavailable.new(path, "#{response.status_code} #{response.body}")
      end

      response.body.strip
    rescue ex : IO::Error | Socket::Error
      raise Unavailable.new(path, ex.message.to_s)
    end
  end
end
