require "http/server"

# A stand-in for a git host's API, backed by recorded fixtures.
#
# Specs drive the real crawler over a real socket against this, so pagination,
# header-driven cursors, rate-limit handling and retries are exercised through
# the same code that talks to GitHub, not around it. What it deliberately does
# not do is talk to a real host: the response bodies are recordings, and the
# scripted statuses are how a rate limit or a flaky page is reproduced on demand.
class FakeHost
  record Response,
    status : Int32 = 200,
    body : String = "{}",
    headers : Hash(String, String) = {} of String => String

  # Every request the crawler made, in order, as "GET /path?query".
  getter requests : Array(String) = [] of String

  def initialize
    @routes = [] of {Regex, Proc(String, Int32, Response)}
    @server = uninitialized HTTP::Server
    @address = uninitialized Socket::IPAddress
  end

  # Registers a handler for paths matching `pattern`. The handler receives the
  # full request target and how many times this route has been hit already, so a
  # spec can answer the request that was actually made ("which page, which size
  # window") as well as say "rate limit the first attempt, then answer".
  def on(pattern : Regex, &handler : String, Int32 -> Response) : FakeHost
    @routes << {pattern, handler}
    self
  end

  # Where the crawler should point its API base.
  def base_url : String
    "http://#{@address}"
  end

  # How many requests hit paths matching `pattern`.
  def request_count(pattern : Regex) : Int32
    requests.count(&.matches?(pattern))
  end

  def start : FakeHost
    hits = Hash(Int32, Int32).new(0)

    @server = HTTP::Server.new do |context|
      request = context.request
      target = request.resource
      @requests << "#{request.method} #{target}"

      index = @routes.index { |(pattern, _)| target.matches?(pattern) }

      if index
        _pattern, handler = @routes[index]
        count = hits[index]
        hits[index] = count + 1

        response = handler.call(target, count)
        context.response.status_code = response.status
        response.headers.each { |name, value| context.response.headers[name] = value }
        context.response.content_type = "application/json" unless response.headers.has_key?("Content-Type")
        context.response.print response.body
      else
        context.response.status_code = 404
        context.response.print %({"message":"no fixture for #{target}"})
      end
    rescue
      # The client walking away mid-response is normal in these specs and must
      # not take the run down.
      nil
    end

    @address = @server.bind_unused_port
    spawn { @server.listen }
    # Let the accept loop have a turn before anything connects.
    Fiber.yield
    self
  end

  def stop
    @server.close
  end

  def self.run(&) : Nil
    host = new.start
    begin
      yield host
    ensure
      host.stop
    end
  end
end

# A sleeper that records what it was asked to wait instead of waiting, so backoff
# is asserted rather than endured.
class RecordedSleeper
  getter waits : Array(Time::Span) = [] of Time::Span

  def to_proc : Proc(Time::Span, Nil)
    ->(duration : Time::Span) do
      @waits << duration
      nil
    end
  end

  def total : Time::Span
    waits.sum(Time::Span.zero)
  end
end
