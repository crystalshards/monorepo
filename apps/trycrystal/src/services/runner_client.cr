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
      headers: HTTP::Headers{"Content-Type" => "application/json"},
      body: request_body
    )

    unless response.status.success?
      raise BadResponse.new(
        "runner at #{settings.url} answered #{response.status.code}, " \
        "expected 200 with the execution contract"
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
end
