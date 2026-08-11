require "./client"
require "./errors"
require "./posting"
require "./application_payload"

module CrystalGigs
  module Ats
    # What an adapter hands back after the provider accepted an application.
    struct Receipt
      getter reference : String?
      getter status : Int32

      def initialize(@status : Int32, @reference : String? = nil)
      end
    end

    # The one interface every ATS integration implements.
    #
    # Adding a third ATS means adding a subclass and one `Registry.register`
    # line at the bottom of its file. Nothing in the actions, the importer or
    # the handoff service knows a provider name.
    abstract class Adapter
      # Stable provider key. Stored on `AtsConnection#provider` and
      # `Job#source`, and used for the credential environment variable lookup.
      abstract def key : String

      # Human name, used in messages shown to employers and operators.
      abstract def display_name : String

      # Public job board endpoint for a board token.
      abstract def board_url(board_token : String) : String

      # Parse a board payload into normalised postings. Pure: no network, so
      # specs exercise it against recorded fixtures.
      abstract def parse_postings(payload : String) : Array(Posting)

      # Whether this provider accepts applications over an API.
      abstract def supports_application_api? : Bool

      # Submit an application. Returns a `Receipt` on success and raises an
      # `Ats::Error` on any failure. Implementations must not swallow errors:
      # the handoff service decides what a failure means for the candidate.
      abstract def submit_application(
        board_token : String,
        external_id : String,
        payload : ApplicationPayload,
        client : Client,
      ) : Receipt

      # Fetch and parse in one step. HTTP lives here so adapters stay parsers.
      def fetch_postings(board_token : String, client : Client) : Array(Posting)
        token = board_token.strip
        raise Error.new("#{display_name} board token is blank") if token.empty?

        response = client.get(board_url(token))
        unless response.success?
          raise UpstreamError.new(
            "#{display_name} board '#{token}' returned HTTP #{response.status}",
            response.status
          )
        end

        parse_postings(response.body)
      end

      # Whether outbound submission is possible right now: the provider has an
      # API and its credential is configured.
      def application_api_available? : Bool
        supports_application_api? && CrystalGigs::AtsConfig.credential_configured?(key)
      end

      # The credential this adapter needs. Fails closed when unset.
      def api_key : String
        CrystalGigs::AtsConfig.api_key(key)
      end

      def credential_env_key : String
        CrystalGigs::AtsConfig.env_key_for(key)
      end

      private def parse_json(payload : String) : JSON::Any
        JSON.parse(payload)
      rescue ex : JSON::ParseException
        raise ParseError.new("#{display_name} returned a payload that is not JSON: #{ex.message}")
      end
    end
  end
end
