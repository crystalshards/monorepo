require "http/client"
require "json"
require "uri"
require "carbon"

# Carbon adapter for Resend.
#
# There is no published Carbon adapter for Resend, so this is ours. It is
# deliberately small: one POST, one check of the answer, no retry policy and no
# queue of its own. Anything cleverer belongs at the call site, where that
# caller's own failure semantics already live.
#
# Checking the answer is the point of this file. An adapter that posts and
# ignores the response is a mail system that reports success while sending
# nothing: the app boots, the operation returns, the request logs a 200, and
# the message never arrives. Every non-2xx therefore raises, carrying Resend's
# status and body so the failure is diagnosable from the exception alone
# without turning on request logging in production.
#
# This file is intentionally identical in every app that sends mail. The apps
# build as independent images with `apps/<app>` as the docker context, so
# nothing outside an app directory reaches its image and there is no shared
# shard to hold this. Keeping the copies byte-identical makes a later
# extraction a move rather than a merge, and makes drift a one-line `cmp`.
class Carbon::ResendAdapter < Carbon::Adapter
  ENDPOINT = "https://api.resend.com/emails"

  # The one place the variable name is written. Both the working adapter and
  # the message a send raises without it read it from here, so they can never
  # name different variables.
  KEY_VARIABLE = "RESEND_API_KEY"

  # Picks the adapter from the environment. `sends` describes what this app
  # sends and appears in the exception raised when there is no key.
  #
  # Adding the key is the entire deployment step: no code change, no flag, no
  # second adapter to remember to swap in.
  def self.from_env(sends : String) : Carbon::Adapter
    if key = ENV[KEY_VARIABLE]?.presence
      new(api_key: key)
    else
      Unavailable.new(sends)
    end
  end

  class Error < Exception
  end

  # Resend answered, and the answer was not a success. Both the status and the
  # body are kept as fields as well as being formatted into the message, so a
  # caller can branch on the status without parsing prose.
  #
  # Nothing from the request goes in here. The request carries the bearer
  # token, and a message built from it is how an API key ends up in a log.
  class DeliveryFailed < Error
    getter status : Int32
    getter body : String

    def initialize(@status : Int32, @body : String)
      super("Resend refused the message: HTTP #{@status}: #{@body}")
    end
  end

  # Raised by `Unavailable` when the app tried to send and there is no key.
  class NotConfigured < Error
  end

  # What an app that sends mail uses in production when RESEND_API_KEY is
  # absent. It is not a fallback and it delivers nothing: every send raises,
  # naming the variable and what went undelivered.
  #
  # This exists because refusing to boot was the wrong blast radius. A job
  # board that will not serve its homepage because mail is unconfigured has
  # turned a missing feature into an outage. Serving is the primary function;
  # mail is a feature, so the feature fails closed and the process does not.
  #
  # `Carbon::DevAdapter` is the trap this avoids. It accepts the message,
  # records it and returns success, so the caller logs a delivery that never
  # happened. That is the defect class this whole change exists to remove, and
  # it is worse in production than an exception is.
  class Unavailable < Carbon::Adapter
    def initialize(@sends : String, @variable : String = KEY_VARIABLE)
    end

    def deliver_now(email : Carbon::Email)
      raise NotConfigured.new(<<-MESSAGE)
      #{@variable} is not set, so #{@sends} cannot be sent.

      The site is running and serving normally; mail is the only thing that is
      unavailable. Nothing was delivered and nothing was queued, and this
      exception is raised rather than swallowed so no caller records a send
      that did not happen.

      Set #{@variable} to a real Resend API key and redeploy.
      MESSAGE
    end

    # Later or not, there is still no key. Raising here rather than deferring
    # keeps the two paths reporting the same thing.
    def deliver_later(email : Carbon::Email)
      deliver_now(email)
    end
  end

  struct Response
    getter status : Int32
    getter body : String

    def initialize(@status : Int32, @body : String)
    end

    def success? : Bool
      status >= 200 && status < 300
    end
  end

  # The single seam between the adapter and the network, so the request this
  # builds can be asserted on without a socket and without a Resend account.
  abstract class Transport
    abstract def post(url : String, headers : HTTP::Headers, body : String) : Response
  end

  class HttpTransport < Transport
    CONNECT_TIMEOUT = 10.seconds
    READ_TIMEOUT    = 20.seconds

    def post(url : String, headers : HTTP::Headers, body : String) : Response
      uri = URI.parse(url)
      client = HTTP::Client.new(uri)
      client.connect_timeout = CONNECT_TIMEOUT
      client.read_timeout = READ_TIMEOUT

      begin
        response = client.post(uri.request_target, headers: headers, body: body)
        Response.new(response.status_code, response.body)
      ensure
        client.close
      end
    end
  end

  private getter api_key : String
  private getter transport : Transport
  private getter deliver_later_strategy : Carbon::DeliverLaterStrategy

  def initialize(
    @api_key : String,
    @transport : Transport = HttpTransport.new,
    @deliver_later_strategy : Carbon::DeliverLaterStrategy = Carbon::SpawnStrategy.new,
  )
  end

  def deliver_now(email : Carbon::Email) : Response
    response = transport.post(ENDPOINT, request_headers, payload(email))
    raise DeliveryFailed.new(response.status, response.body) unless response.success?
    response
  end

  # Carbon's own `Email#deliver_later` routes through the deliver-later
  # strategy configured on the email class and never reaches this method; it
  # is here so the adapter is complete on its own terms for a caller holding
  # the adapter directly.
  #
  # A refusal still raises. Under the default `Carbon::SpawnStrategy` that
  # surfaces as an unhandled exception on the delivering fiber rather than at
  # the call site, which is the cost of asking for a send to happen later, but
  # it is still a report of failure rather than silence.
  def deliver_later(email : Carbon::Email)
    deliver_later_strategy.run(email) do
      deliver_now(email)
    end
  end

  private def request_headers : HTTP::Headers
    HTTP::Headers{
      "Authorization" => "Bearer #{api_key}",
      "Content-Type"  => "application/json",
    }
  end

  private def payload(email : Carbon::Email) : String
    reply_to, headers = split_reply_to(email.headers)

    JSON.build do |json|
      json.object do
        json.field "from", email.from.to_s
        addresses(json, "to", email.to)
        json.field "subject", email.subject

        # Omitted rather than sent empty. Resend rejects an empty part, and
        # these apps genuinely send single-part mail: CrystalGigs' job
        # application email is text-only on purpose, because it carries
        # candidate-supplied content that must never become markup in a
        # recruiter's inbox.
        if html = presence(email.html_body)
          json.field "html", html
        end

        if text = presence(email.text_body)
          json.field "text", text
        end

        addresses(json, "cc", email.cc) unless email.cc.empty?
        addresses(json, "bcc", email.bcc) unless email.bcc.empty?

        json.field "reply_to", reply_to if reply_to

        unless headers.empty?
          json.field "headers" do
            json.object do
              headers.each { |name, value| json.field name, value }
            end
          end
        end
      end
    end
  end

  private def addresses(json : JSON::Builder, name : String, values : Array(Carbon::Address)) : Nil
    json.field name do
      json.array do
        values.each { |address| json.string(address.to_s) }
      end
    end
  end

  # Carbon has no reply_to field. `reply_to "x@y"` writes a Reply-To header,
  # so the header is lifted into Resend's first-class field here; the rest are
  # passed through as custom headers rather than discarded.
  private def split_reply_to(headers : Hash(String, String)) : {String?, Hash(String, String)}
    reply_to = nil
    rest = {} of String => String

    headers.each do |name, value|
      if name.downcase == "reply-to"
        reply_to = value
      else
        rest[name] = value
      end
    end

    {reply_to, rest}
  end

  private def presence(body) : String?
    return nil unless body.is_a?(String)
    body.empty? ? nil : body
  end
end
