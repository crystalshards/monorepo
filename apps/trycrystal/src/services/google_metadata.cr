require "http/client"
require "json"

module TryCrystal
  # The ambient Cloud Run identity, read from the instance metadata server.
  #
  # Nothing here is a credential in source. The metadata server is only
  # reachable from inside a Google-managed instance and answers with the
  # identity the deployment already assigned to this revision, so there is no
  # key to leak, rotate or accidentally commit.
  #
  # Not reachable in development or test, and never called there: the runner is
  # unauthenticated locally, so RunnerClient only asks for a token when an
  # audience is configured, which happens in production only.
  #
  # This follows the GoogleMetadata module the four sibling apps already carry,
  # deliberately, rather than introducing a fifth shape for the same job. The
  # one addition is identity_token, because this app is the first here that has
  # to prove WHO it is to another Cloud Run service rather than call a Google
  # API as itself.
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

    # A Google-signed OIDC token asserting this revision's identity to one
    # audience, for calling a Cloud Run service that is locked to this app's
    # service account.
    #
    # The audience is a declared literal that the runner also declares in
    # custom_audiences, so Cloud Run accepts a token bearing it. Both sides read
    # the same terraform local and therefore cannot drift; see
    # local.trycrystal_runner_audience.
    #
    # Deliberately not cached, for the same reason access_token is not in the
    # sibling apps: the metadata server caches and refreshes underneath, and
    # holding the string here would mean keeping an expiring credential in
    # memory past its validity. That surfaces as a 403 on the one path a
    # visitor is waiting on, long after the deploy that looked fine.
    #
    # The response body is the raw JWT, not JSON, unlike the OAuth token
    # endpoint.
    def self.identity_token(audience : String) : String
      get("/computeMetadata/v1/instance/service-accounts/default/identity" \
          "?audience=#{URI.encode_www_form(audience)}")
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
