# The HTTP surface. Exactly two endpoints, one JSON shape each.

module TryCrystalRunner
  class HTTPServer
    def initialize(@config : Config, @executor : Executor, @crystal_version : String)
    end

    def start
      server = HTTP::Server.new do |context|
        handle(context)
      end

      address = server.bind_tcp("0.0.0.0", @config.port)
      STDERR.puts "trycrystal-runner: listening on #{address} " \
                  "(#{@config.confined? ? "confined" : "ALLOW_UNSAFE"}, " \
                  "crystal #{@crystal_version})"
      server.listen
    end

    private def handle(context : HTTP::Server::Context)
      case {context.request.method, context.request.path}
      when {"GET", "/health"}
        respond_json(context, 200) do |json|
          json.object do
            json.field "status", "ok"
            json.field "crystal_version", @crystal_version
          end
        end
      when {"POST", "/execute"}
        execute(context)
      else
        respond_json(context, 404) do |json|
          json.object { json.field "error", "not found" }
        end
      end
    end

    private def execute(context : HTTP::Server::Context)
      body = context.request.body
      unless body
        return respond_json(context, 400) { |json| json.object { json.field "error", "request body required" } }
      end

      begin
        payload = JSON.parse(body)
      rescue ex : JSON::ParseException
        return respond_json(context, 400) { |json| json.object { json.field "error", "invalid JSON: #{ex.message}" } }
      end

      code = payload["code"]?.try &.as_s?
      unless code
        return respond_json(context, 400) { |json| json.object { json.field "error", "code must be a string" } }
      end

      timeout_ms = @config.default_timeout_ms
      if raw = payload["timeout_ms"]?
        unless raw.as_i?
          return respond_json(context, 400) { |json| json.object { json.field "error", "timeout_ms must be an integer" } }
        end
        timeout_ms = raw.as_i
      end

      result = @executor.execute(code, timeout_ms)

      respond_json(context, 200) do |json|
        result.to_json(json)
      end
    rescue ex : Exception
      STDERR.puts "trycrystal-runner: internal error: #{ex.class} #{ex.message}\n#{ex.backtrace.try(&.first(8).join("\n"))}"
      respond_json(context, 500) do |json|
        json.object { json.field "error", "internal error" }
      end
    end

    # The builder is yielded bare so a caller can stream a whole object of
    # its own (Result#to_json) or a single-field envelope, never both.
    private def respond_json(context : HTTP::Server::Context, status : Int32)
      context.response.status_code = status
      context.response.content_type = "application/json"
      JSON.build(context.response) do |json|
        yield json
      end
    end
  end
end
