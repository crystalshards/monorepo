class BrowserClient < Lucky::BaseHTTPClient
  app AppServer.new

  # BrowserClient for testing BrowserActions (HTML format)
  # Does not set Content-Type to allow Lucky to handle format negotiation
  # Use ApiClient for testing API endpoints
end
