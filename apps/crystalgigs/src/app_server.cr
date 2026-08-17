class AppServer < Lucky::BaseAppServer
  # Learn about middleware with HTTP::Handlers:
  # https://luckyframework.org/guides/http-and-routing/http-handlers
  def middleware : Array(HTTP::Handler)
    [
      Lucky::RequestIdHandler.new,
      Lucky::ForceSSLHandler.new,
      Lucky::HttpMethodOverrideHandler.new,
      Lucky::LogHandler.new,
      Lucky::ErrorHandler.new(action: Errors::Show),
      Lucky::RemoteIpHandler.new,
      # Records the page view from the response's final status. It sits
      # inside ErrorHandler so an action that raises reaches it as the 500
      # the error page became (which it refuses) rather than as an exception
      # through it, and after ForceSSLHandler so the http-to-https redirect
      # never reaches it and the visit is counted once, by the https request
      # that follows. Everything further in -- routing, static files, and the
      # not-found handler -- reports its status here, which is what the
      # collector refuses assets, 404s and 500s on.
      PageViewHandler.new,
      Lucky::RouteHandler.new,

      Lucky::StaticCompressionHandler.new("./public", file_ext: "gz", content_encoding: "gzip"),
      Lucky::StaticFileHandler.new("./public", fallthrough: false, directory_listing: false),
      Lucky::RouteNotFoundHandler.new,
    ] of HTTP::Handler
  end

  def protocol
    "http"
  end

  def listen
    server.listen(host, port, reuse_port: false)
  end
end
