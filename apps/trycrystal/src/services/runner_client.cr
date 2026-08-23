require "http/client"

# The web app's one door to the sandbox. Speaks the runner's single endpoint
# contract exactly as DESIGN.md fixes it:
#
#   POST {url}/execute  {"code": "<crystal source>", "timeout_ms": 20000}
#   200 {"stdout": "...", "stderr": "...", "value": "...", "exit_code": 0,
#        "timed_out": false, "duration_ms": 412}
#
# An error in the user's code is a successful exchange: the runner answers
# HTTP 200 with stderr populated and a non-zero exit_code, and that arrives
# here as an ordinary ExecutionResult. Only the web app failing to talk to
# the runner at all raises, as RunnerClient::Unreachable, which the action
# renders as an in-character message rather than a stack trace.
class RunnerClient
  Habitat.create do
    setting url : String
    # The OIDC audience to mint an identity token for, when the runner is IAM
    # locked. Nil locally, where the runner is unauthenticated and the
    # metadata server does not exist.
    #
    # This exists because the runner's terraform states the contract plainly:
    # the service is locked to this app's identity, "so the URL alone reaches
    # nothing", and the app "mints its ID token for" the audience it declares
    # in custom_audiences. That half was documented in infrastructure and
    # missing from this client, so production answered every submission with
    # "the sandbox is not answering" while the app itself was healthy and the
    # deploy was green. Nothing local could catch it: there is no IAM in front
    # of a runner on localhost.
    setting audience : String? = nil
    # Sized to the measured distribution, not to the worst case anyone can
    # imagine. Interpreter mode, measured through this client: 369ms to
    # 1105ms across the three lessons and stdlib requires. Run mode is the
    # fallback and its cold worst case measured 6334ms. 8000 clears that
    # fallback with headroom and is roughly seven times the interpreter's
    # slowest observed run, while capping what a genuinely hung submission
    # costs a visitor before the console says anything. The old 20000 was
    # sized for run mode's cold case and made a hang a twenty second wait.
    setting execution_timeout_ms : Int32 = 8_000
    setting connect_timeout : Time::Span = 2.seconds
    # Above the execution budget plus compile and transport overhead, and
    # deliberately above the ~15s hard kill observed from the sandbox when
    # its own cap fired ahead of the requested budget: the client must
    # still be listening when the sandbox reports what it did, or a real
    # answer turns into a false "not answering".
    setting read_timeout : Time::Span = 20.seconds
  end

  # The sandbox could not be reached: refused connection, timeout, TLS
  # trouble. Nothing ran, so nothing is reported as having run.
  class Unreachable < Exception
  end

  # The runner answered, but not with the contract. A malformed body is a
  # server bug on the runner side and must not be mistaken for user output.
  class BadResponse < Exception
  end

  def execute(code : String) : ExecutionResult
    request_body = {
      code:       code,
      timeout_ms: settings.execution_timeout_ms,
    }.to_json

    client = HTTP::Client.new(URI.parse(settings.url))
    client.connect_timeout = settings.connect_timeout
    client.read_timeout = settings.read_timeout

    response = client.post(
      "/execute",
      headers: request_headers,
      body: request_body
    )

    unless response.status.success?
      # 401 and 403 are named, because they are not the runner failing: they
      # are Cloud Run refusing the caller before the runner ever sees the
      # request, and they read identically to a broken sandbox from outside.
      hint = case response.status.code
             when 401, 403
               ". Cloud Run rejected this app's identity, so the request never " \
               "reached the runner. Check that the audience the app mints for " \
               "matches the runner's custom_audiences, and that this app's " \
               "service account holds run.invoker on it"
             else
               ""
             end

      raise BadResponse.new(
        "runner at #{settings.url} answered #{response.status.code}, " \
        "expected 200 with the execution contract#{hint}"
      )
    end

    ExecutionResult.from_json(response.body)
  rescue ex : JSON::ParseException | JSON::SerializableError
    raise BadResponse.new(
      "runner at #{settings.url} answered 200 with a body that is not the " \
      "execution contract: #{ex.message}"
    )
  rescue ex : IO::Error | Socket::Error | OpenSSL::SSL::Error | IO::TimeoutError
    raise Unreachable.new(
      "sandbox at #{settings.url} could not be reached: #{ex.class} #{ex.message}"
    )
  end

  # Content type always; an identity token only when an audience is
  # configured, which is production. Locally the runner is unauthenticated and
  # there is no metadata server to ask.
  #
  # A failure to mint the token is Unreachable rather than BadResponse: the
  # request was never sent, so nothing ran, which is exactly what Unreachable
  # means to the caller.
  private def request_headers : HTTP::Headers
    headers = HTTP::Headers{"Content-Type" => "application/json"}

    if audience = settings.audience
      begin
        headers["Authorization"] = "Bearer #{TryCrystal::GoogleMetadata.identity_token(audience)}"
      rescue ex : TryCrystal::GoogleMetadata::Unavailable
        raise Unreachable.new(
          "could not mint an identity token for #{audience}, so the sandbox was " \
          "never called: #{ex.message}"
        )
      end
    end

    headers
  end
end
