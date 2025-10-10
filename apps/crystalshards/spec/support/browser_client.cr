class BrowserClient < Lucky::BaseHTTPClient
  app AppServer.new

  def initialize
    super
    # Request HTML format for BrowserActions
    headers("Accept": "text/html,application/xhtml+xml")
    # Use form-encoded data for POST requests (like HTML forms)
    headers("Content-Type": "application/x-www-form-urlencoded")
  end

  # BrowserClient for testing BrowserActions (HTML format)
  # Use ApiClient for testing API endpoints
end
