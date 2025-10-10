class BrowserClient < Lucky::BaseHTTPClient
  app AppServer.new

  def initialize
    super
    # Request HTML format for BrowserActions
    headers("Accept": "text/html,application/xhtml+xml")
  end

  # BrowserClient for testing BrowserActions (HTML format)
  # Use ApiClient for testing API endpoints
end
