require "http/server"

# A real HTTP server speaking the sandbox's exact contract, so the specs
# exercise the web app's real HTTP client: real socket, real JSON, real
# connection-refused paths. Anything less would test the parsing and miss
# the transport.
#
# The response is a canned contract JSON the spec replaces per case with
# `stub`. The fake never interprets the submitted code: the web app under
# test does not care what the code was, only what came back, which is the
# point of the lesson checks.
class FakeRunner
  def self.start : Nil
    server = HTTP::Server.new do |context|
      if context.request.method == "POST" && context.request.path == "/execute"
        context.response.headers["Content-Type"] = "application/json"
        context.response.print(@@response)
      else
        context.response.respond_with_status(404)
      end
    end

    address = server.bind_tcp("127.0.0.1", 0)
    spawn { server.listen }
    @@server = server
    ENV["RUNNER_URL"] = "http://#{address}"
  end

  def self.url : String
    ENV["RUNNER_URL"].not_nil!
  end

  # Replaces what the sandbox answers for every subsequent /execute.
  def self.stub(stdout : String = "", stderr : String = "", value : String? = nil,
                exit_code : Int32 = 0, timed_out : Bool = false,
                duration_ms : Int64 = 412_i64) : Nil
    @@response = {
      stdout:      stdout,
      stderr:      stderr,
      value:       value,
      exit_code:   exit_code,
      timed_out:   timed_out,
      duration_ms: duration_ms,
    }.to_json
  end

  # A URL whose port is bound then released, so nothing is listening on it:
  # connect is refused, the exact shape of "the sandbox is down".
  def self.dead_url : String
    server = HTTP::Server.new { |context| context.response.respond_with_status(500) }
    address = server.bind_tcp("127.0.0.1", 0)
    server.close
    "http://#{address}"
  end

  @@server : HTTP::Server?
  @@response : String = {
    stdout:      "",
    stderr:      "",
    value:       nil,
    exit_code:   0,
    timed_out:   false,
    duration_ms: 0_i64,
  }.to_json
end
