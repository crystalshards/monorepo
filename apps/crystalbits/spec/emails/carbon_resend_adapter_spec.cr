require "../spec_helper"

# Every example here runs against a recording transport. Nothing in this file
# opens a socket, reads a credential or needs a Resend account: the adapter's
# entire contract is the request it builds and what it does with the answer it
# gets back, and both of those are observable without a network.
private class RecordingTransport < Carbon::ResendAdapter::Transport
  record Sent, url : String, headers : HTTP::Headers, body : String

  getter sent = [] of Sent

  def initialize(@status : Int32 = 200, @response_body : String = %({"id":"5b91"}))
  end

  def post(url : String, headers : HTTP::Headers, body : String) : Carbon::ResendAdapter::Response
    @sent << Sent.new(url, headers, body)
    Carbon::ResendAdapter::Response.new(@status, @response_body)
  end

  def last : Sent
    @sent.last
  end

  def last_body : Hash(String, JSON::Any)
    JSON.parse(last.body).as_h
  end
end

# Runs the delivery on the calling fiber, so an example can observe what a
# send that happens "later" actually did, including the exception it raised.
# `Carbon::SpawnStrategy`, the default, would put both on another fiber.
private class InlineStrategy < Carbon::DeliverLaterStrategy
  def run(email, &block)
    block.call
  end
end

private class ResendTestEmail < Carbon::Email
  property subject : String
  property from : Carbon::Address
  property to : Array(Carbon::Address)
  property cc : Array(Carbon::Address)
  property bcc : Array(Carbon::Address)
  property text_body : String?
  property html_body : String?

  def initialize(
    @subject = "Weekly digest",
    @from = Carbon::Address.new("Crystal News", "news@example.test"),
    @to = [Carbon::Address.new("reader@example.test")],
    @cc = [] of Carbon::Address,
    @bcc = [] of Carbon::Address,
    @text_body = "Plain text body",
    @html_body = "<p>HTML body</p>",
    headers : Hash(String, String) = {} of String => String,
  )
    @headers = headers
  end
end

private API_KEY = "re_spec_0123456789"

private def adapter(
  transport : RecordingTransport = RecordingTransport.new,
  deliver_later_strategy : Carbon::DeliverLaterStrategy = InlineStrategy.new,
) : Carbon::ResendAdapter
  Carbon::ResendAdapter.new(
    api_key: API_KEY,
    transport: transport,
    deliver_later_strategy: deliver_later_strategy
  )
end

# Restores whatever the suite started with, so an example that changes the
# environment cannot change the result of the one after it.
private def with_resend_key(value : String?, &)
  variable = Carbon::ResendAdapter::KEY_VARIABLE
  previous = ENV[variable]?

  begin
    if value.nil?
      ENV.delete(variable)
    else
      ENV[variable] = value
    end

    yield
  ensure
    if previous.nil?
      ENV.delete(variable)
    else
      ENV[variable] = previous
    end
  end
end

describe Carbon::ResendAdapter do
  describe "#deliver_now" do
    it "posts to Resend's send endpoint" do
      transport = RecordingTransport.new
      adapter(transport).deliver_now(ResendTestEmail.new)

      transport.sent.size.should eq(1)
      transport.last.url.should eq("https://api.resend.com/emails")
    end

    it "authenticates with a bearer token and sends JSON" do
      transport = RecordingTransport.new
      adapter(transport).deliver_now(ResendTestEmail.new)

      transport.last.headers["Authorization"].should eq("Bearer #{API_KEY}")
      transport.last.headers["Content-Type"].should eq("application/json")
    end

    it "carries from, to and subject" do
      transport = RecordingTransport.new
      adapter(transport).deliver_now(ResendTestEmail.new(subject: "Issue 12"))

      body = transport.last_body
      body["from"].as_s.should eq(%("Crystal News" <news@example.test>))
      body["to"].as_a.map(&.as_s).should eq(["reader@example.test"])
      body["subject"].as_s.should eq("Issue 12")
    end

    it "carries both bodies when the email has both" do
      transport = RecordingTransport.new
      adapter(transport).deliver_now(
        ResendTestEmail.new(text_body: "Read it here", html_body: "<p>Read it here</p>")
      )

      body = transport.last_body
      body["text"].as_s.should eq("Read it here")
      body["html"].as_s.should eq("<p>Read it here</p>")
    end

    # CrystalGigs' JobApplicationEmail is deliberately text-only, because it
    # carries candidate-supplied content. Sending `"html": null` or an empty
    # string for it is a 422 from Resend, so the key is omitted instead.
    it "omits html for a text-only email" do
      transport = RecordingTransport.new
      adapter(transport).deliver_now(ResendTestEmail.new(html_body: nil))

      body = transport.last_body
      body.has_key?("html").should be_false
      body["text"].as_s.should eq("Plain text body")
    end

    it "omits text for an html-only email" do
      transport = RecordingTransport.new
      adapter(transport).deliver_now(ResendTestEmail.new(text_body: nil))

      body = transport.last_body
      body.has_key?("text").should be_false
      body["html"].as_s.should eq("<p>HTML body</p>")
    end

    it "treats an empty body as no body rather than sending an empty part" do
      transport = RecordingTransport.new
      adapter(transport).deliver_now(ResendTestEmail.new(html_body: ""))

      transport.last_body.has_key?("html").should be_false
    end

    it "carries every recipient, not just the first" do
      transport = RecordingTransport.new
      adapter(transport).deliver_now(ResendTestEmail.new(to: [
        Carbon::Address.new("one@example.test"),
        Carbon::Address.new("Two", "two@example.test"),
      ]))

      transport.last_body["to"].as_a.map(&.as_s).should eq([
        "one@example.test",
        %("Two" <two@example.test>),
      ])
    end

    it "carries cc and bcc when the email sets them" do
      transport = RecordingTransport.new
      adapter(transport).deliver_now(ResendTestEmail.new(
        cc: [Carbon::Address.new("cc@example.test")],
        bcc: [Carbon::Address.new("bcc@example.test")],
      ))

      body = transport.last_body
      body["cc"].as_a.map(&.as_s).should eq(["cc@example.test"])
      body["bcc"].as_a.map(&.as_s).should eq(["bcc@example.test"])
    end

    it "omits cc and bcc when the email sets neither" do
      transport = RecordingTransport.new
      adapter(transport).deliver_now(ResendTestEmail.new)

      body = transport.last_body
      body.has_key?("cc").should be_false
      body.has_key?("bcc").should be_false
    end

    # Carbon has no reply_to field: `reply_to "x@y"` writes a Reply-To header.
    # Resend has a first-class reply_to, so the header is lifted into it. A
    # job application whose reply address is dropped reaches the employer with
    # no way back to the candidate, which is the whole point of that email.
    it "lifts Reply-To out of the headers into reply_to" do
      transport = RecordingTransport.new
      adapter(transport).deliver_now(
        ResendTestEmail.new(headers: {"Reply-To" => "candidate@example.test"})
      )

      body = transport.last_body
      body["reply_to"].as_s.should eq("candidate@example.test")
      body.has_key?("headers").should be_false
    end

    it "passes any other header through rather than dropping it" do
      transport = RecordingTransport.new
      adapter(transport).deliver_now(ResendTestEmail.new(headers: {
        "Reply-To"         => "candidate@example.test",
        "X-Entity-Ref-ID"  => "application-42",
        "List-Unsubscribe" => "<https://example.test/u/42>",
      }))

      headers = transport.last_body["headers"].as_h
      headers["X-Entity-Ref-ID"].as_s.should eq("application-42")
      headers["List-Unsubscribe"].as_s.should eq("<https://example.test/u/42>")
      headers.has_key?("Reply-To").should be_false
    end

    it "omits reply_to and headers when the email sets none" do
      transport = RecordingTransport.new
      adapter(transport).deliver_now(ResendTestEmail.new)

      body = transport.last_body
      body.has_key?("reply_to").should be_false
      body.has_key?("headers").should be_false
    end

    # The two halves of the guard. A check only ever observed passing is not a
    # check: the 2xx example is what proves the 4xx example is failing for the
    # reason claimed and not because delivery is broken outright.
    it "returns Resend's answer on 2xx without raising" do
      transport = RecordingTransport.new(status: 202, response_body: %({"id":"5b91"}))

      response = adapter(transport).deliver_now(ResendTestEmail.new)

      response.status.should eq(202)
      response.success?.should be_true
      response.body.should eq(%({"id":"5b91"}))
    end

    it "raises on 4xx, naming the status and the body Resend sent" do
      transport = RecordingTransport.new(
        status: 422,
        response_body: %({"statusCode":422,"message":"The from address is not verified"})
      )

      error = expect_raises(Carbon::ResendAdapter::DeliveryFailed) do
        adapter(transport).deliver_now(ResendTestEmail.new)
      end

      error.status.should eq(422)
      error.body.should contain("not verified")
      message = error.message.to_s
      message.should contain("422")
      message.should contain("The from address is not verified")
    end

    it "raises on 5xx as well, so an outage is never reported as a send" do
      transport = RecordingTransport.new(status: 503, response_body: "upstream unavailable")

      error = expect_raises(Carbon::ResendAdapter::DeliveryFailed) do
        adapter(transport).deliver_now(ResendTestEmail.new)
      end

      error.status.should eq(503)
      error.message.to_s.should contain("upstream unavailable")
    end

    # The bearer token is on the request that failed, so a message built from
    # the request rather than the response is how a key reaches a log.
    it "keeps the API key out of the failure message" do
      transport = RecordingTransport.new(status: 401, response_body: %({"message":"Invalid API key"}))

      error = expect_raises(Carbon::ResendAdapter::DeliveryFailed) do
        adapter(transport).deliver_now(ResendTestEmail.new)
      end

      error.message.to_s.should_not contain(API_KEY)
    end
  end

  describe "#deliver_later" do
    it "delivers through the configured strategy" do
      transport = RecordingTransport.new

      adapter(transport).deliver_later(ResendTestEmail.new(subject: "Sent later"))

      transport.sent.size.should eq(1)
      transport.last_body["subject"].as_s.should eq("Sent later")
    end

    it "propagates a refusal rather than swallowing it" do
      transport = RecordingTransport.new(status: 429, response_body: "rate limited")

      error = expect_raises(Carbon::ResendAdapter::DeliveryFailed) do
        adapter(transport).deliver_later(ResendTestEmail.new)
      end

      error.status.should eq(429)
    end
  end

  # Production without a key. The site serves; mail is loudly unavailable.
  describe Carbon::ResendAdapter::Unavailable do
    it "raises on a send, naming the variable and what went undelivered" do
      unavailable = Carbon::ResendAdapter::Unavailable.new("the weekly newsletter")

      error = expect_raises(Carbon::ResendAdapter::NotConfigured) do
        unavailable.deliver_now(ResendTestEmail.new)
      end

      message = error.message.to_s
      message.should contain("RESEND_API_KEY")
      message.should contain("the weekly newsletter")
    end

    # The whole reason this class exists rather than reusing DevAdapter: a
    # send must never come back successful when nothing was sent.
    it "raises on a later send too, rather than reporting success" do
      unavailable = Carbon::ResendAdapter::Unavailable.new("the weekly newsletter")

      expect_raises(Carbon::ResendAdapter::NotConfigured) do
        unavailable.deliver_later(ResendTestEmail.new)
      end
    end
  end

  # Adding the GitHub secret is the entire deployment step, so the switch from
  # unavailable to working has to be the environment and nothing else.
  describe ".from_env" do
    it "builds a working adapter once the key is present" do
      with_resend_key("re_live_abc") do
        Carbon::ResendAdapter.from_env("the weekly newsletter")
          .should be_a(Carbon::ResendAdapter)
      end
    end

    it "builds the unavailable adapter when the key is absent" do
      with_resend_key(nil) do
        Carbon::ResendAdapter.from_env("the weekly newsletter")
          .should be_a(Carbon::ResendAdapter::Unavailable)
      end
    end

    # An empty secret version is the shape this actually fails in, and an
    # empty string would otherwise be accepted as a key and rejected by
    # Resend on every single send.
    it "treats an empty key as no key" do
      with_resend_key("") do
        Carbon::ResendAdapter.from_env("the weekly newsletter")
          .should be_a(Carbon::ResendAdapter::Unavailable)
      end
    end
  end
end
