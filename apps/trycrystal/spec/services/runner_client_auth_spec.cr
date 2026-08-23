require "../spec_helper"

# The runner is IAM locked in production, so the app must prove who it is.
#
# This exists because the contract was stated in terraform ("the runner is IAM
# locked to this app's identity, so the URL alone reaches nothing", and the app
# "mints its ID token for" the declared audience) and was not implemented in the
# client. Every local proof passed, because a runner on localhost has no IAM in
# front of it, and production answered every submission with "the sandbox is not
# answering" behind a fully green deploy.
#
# What is assertable without Google: whether an Authorization header is
# attempted at all, keyed on the audience setting. That is the exact bit that
# was missing.
describe RunnerClient do
  describe "when no audience is configured (development)" do
    it "sends no Authorization header and reaches the runner unauthenticated" do
      received = nil.as(HTTP::Headers?)

      server = HTTP::Server.new do |context|
        received = context.request.headers.dup
        context.response.content_type = "application/json"
        context.response.print({
          stdout:      "ok\n",
          stderr:      "",
          value:       "nil",
          exit_code:   0,
          timed_out:   false,
          duration_ms: 1,
        }.to_json)
      end

      address = server.bind_unused_port
      spawn { server.listen }
      Fiber.yield

      begin
        temp_config(url: "http://#{address}", audience: nil) do
          RunnerClient.new.execute(%(puts "ok")).stdout.should eq("ok\n")
        end
      ensure
        server.close
      end

      headers = received.should_not be_nil
      headers["Authorization"]?.should be_nil
      headers["Content-Type"].should eq("application/json")
    end
  end

  describe "when an audience IS configured (production shape)" do
    it "refuses to call the runner unauthenticated, and says nothing ran" do
      # The metadata server does not exist here, so minting must fail. The
      # assertion is that the failure happens BEFORE the request and is
      # reported as Unreachable, because nothing ran. Were the client still
      # sending an unauthenticated request, this would reach the server below
      # and succeed, which is the regression this guards.
      reached = false

      server = HTTP::Server.new do |context|
        reached = true
        context.response.print("{}")
      end

      address = server.bind_unused_port
      spawn { server.listen }
      Fiber.yield

      begin
        temp_config(url: "http://#{address}", audience: "https://runner.invalid") do
          error = expect_raises(RunnerClient::Unreachable) do
            RunnerClient.new.execute("1 + 1")
          end

          error.message.to_s.should contain("identity token")
          error.message.to_s.should contain("never called")
        end
      ensure
        server.close
      end

      reached.should be_false
    end
  end
end

# Habitat settings are process global, so they are restored afterwards rather
# than left mutated for whatever spec runs next.
private def temp_config(url : String, audience : String?, &)
  previous_url = RunnerClient.settings.url
  previous_audience = RunnerClient.settings.audience

  RunnerClient.configure do |settings|
    settings.url = url
    settings.audience = audience
  end

  yield
ensure
  RunnerClient.configure do |settings|
    settings.url = previous_url.to_s
    settings.audience = previous_audience
  end
end
