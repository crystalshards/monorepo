class BrowserClient < Lucky::BaseHTTPClient
  app AppServer.new

  def initialize
    super
    # Request HTML format for BrowserActions
    headers("Accept": "text/html")
  end
end
