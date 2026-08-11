require "http/client"
require "http/formdata"
require "uri"
require "./errors"

module CrystalGigs
  module Ats
    struct Response
      getter status : Int32
      getter body : String

      def initialize(@status : Int32, @body : String)
      end

      def success? : Bool
        status >= 200 && status < 300
      end
    end

    # The single seam between adapters and the network.
    #
    # Adapters build their own request bodies (providers disagree about
    # encoding) and hand a finished body to the client. Specs substitute a
    # client that replays recorded payloads, which is why no adapter is
    # allowed to reach for `HTTP::Client` directly.
    abstract class Client
      abstract def get(url : String, headers : HTTP::Headers) : Response
      abstract def post(url : String, headers : HTTP::Headers, body : String) : Response

      def get(url : String) : Response
        get(url, HTTP::Headers.new)
      end
    end

    class HttpClient < Client
      CONNECT_TIMEOUT = 10.seconds
      READ_TIMEOUT    = 20.seconds
      USER_AGENT      = "CrystalGigs-ATS/1.0 (+https://crystalgigs.org)"

      def get(url : String, headers : HTTP::Headers) : Response
        execute(url) do |client, uri|
          client.get(request_target(uri), headers: with_defaults(headers))
        end
      end

      def post(url : String, headers : HTTP::Headers, body : String) : Response
        execute(url) do |client, uri|
          client.post(request_target(uri), headers: with_defaults(headers), body: body)
        end
      end

      # Nothing in here may put a raw URL into a message. Lever authenticates
      # with `?key=`, so a URL is a credential.
      private def execute(url : String, &) : Response
        uri = begin
          URI.parse(url)
        rescue ex : URI::Error
          raise TransportError.new("Cannot parse ATS URL #{Ats.redact_url(url)}: #{ex.message}")
        end

        raise TransportError.new("Cannot request #{Ats.redact_url(url)}: no host in URL") if uri.host.nil?

        client = HTTP::Client.new(uri)
        client.connect_timeout = CONNECT_TIMEOUT
        client.read_timeout = READ_TIMEOUT
        begin
          response = yield client, uri
          Response.new(response.status_code, response.body)
        rescue ex : IO::Error | Socket::Error | OpenSSL::Error
          raise TransportError.new("Request to #{Ats.redact_url(url)} failed: #{ex.message}")
        ensure
          client.close
        end
      end

      private def request_target(uri : URI) : String
        target = uri.request_target
        target.empty? ? "/" : target
      end

      private def with_defaults(headers : HTTP::Headers) : HTTP::Headers
        merged = headers.dup
        merged["User-Agent"] = USER_AGENT unless merged.has_key?("User-Agent")
        merged["Accept"] = "application/json" unless merged.has_key?("Accept")
        merged
      end
    end

    # Builds the client used by the importer and the handoff service.
    # Specs swap the factory rather than threading a client through every call.
    @@client_factory : Proc(Client) = -> { HttpClient.new.as(Client) }

    def self.client_factory : Proc(Client)
      @@client_factory
    end

    # Pass a proc whose return type is `Client`, not a concrete subclass:
    # `->{ my_client.as(CrystalGigs::Ats::Client) }`.
    def self.client_factory=(factory : Proc(Client))
      @@client_factory = factory
    end

    def self.build_client : Client
      @@client_factory.call
    end

    # Query parameters that carry a credential. Lever authenticates its apply
    # endpoint with `?key=`, so a Lever URL is a secret.
    CREDENTIAL_QUERY_KEYS = %w[key api_key apikey token access_token secret]

    # Deliberately free of characters that percent-encode: the token is
    # re-serialised into a query string, and `key=REDACTED` stays readable in
    # a log where `key=%5Bredacted%5D` does not.
    REDACTED = "REDACTED"

    # A URL safe to put in an exception, a log line or a report.
    #
    # This exists so the safety does not depend on nobody ever adding request
    # logging or an exception reporter: any URL that reaches a message goes
    # through here, and a credential in a query string is replaced rather than
    # printed. Unparseable input is dropped entirely rather than echoed.
    def self.redact_url(url : String) : String
      uri = URI.parse(url)
      query = uri.query
      return url if query.nil? || query.empty?

      params = URI::Params.parse(query)
      redacted = false

      CREDENTIAL_QUERY_KEYS.each do |key|
        next unless params.has_key?(key)
        params[key] = REDACTED
        redacted = true
      end

      return url unless redacted

      uri.query = params.to_s
      uri.to_s
    rescue URI::Error
      "[unparseable url]"
    end

    # `application/x-www-form-urlencoded` body.
    def self.encode_form(fields : Hash(String, String)) : String
      params = URI::Params.new
      fields.each { |key, value| params.add(key, value) }
      params.to_s
    end

    # `multipart/form-data` body. Returns the body and the content type
    # carrying the generated boundary.
    def self.encode_multipart(fields : Hash(String, String)) : {String, String}
      io = IO::Memory.new
      content_type = ""
      HTTP::FormData.build(io) do |builder|
        fields.each { |key, value| builder.field(key, value) }
        content_type = builder.content_type
      end
      {io.to_s, content_type}
    end
  end
end
