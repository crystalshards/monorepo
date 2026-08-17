require "http/client"
require "json"

module CrystalShards
  # The ambient Cloud Run identity, read from the instance metadata server.
  #
  # Nothing here is a credential in source. The metadata server is only
  # reachable from inside a Google-managed instance and answers with the
  # identity the deployment already assigned to this revision, so there is no
  # key to leak, rotate or accidentally commit.
  #
  # Not reachable in development or test, and never called there.
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

    # Explicitly typed: an unannotated `@@ivar ||=` cannot be inferred, and
    # the first call site to hit that was SearchConsole, which is also the
    # first caller of service_account_email at all.
    @@service_account_email : String?

    def self.service_account_email : String
      @@service_account_email ||= get("/computeMetadata/v1/instance/service-accounts/default/email")
    end

    # A short-lived OAuth token for calling Google APIs as this revision.
    #
    # Deliberately not cached. The metadata server caches and refreshes
    # underneath, and holding the string here would mean keeping an expiring
    # credential in memory past its validity, which surfaces as a 401 on a path
    # that only runs while someone is waiting for a build.
    def self.access_token : String
      body = get("/computeMetadata/v1/instance/service-accounts/default/token")

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
