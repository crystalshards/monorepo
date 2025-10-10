class ApiClient < Lucky::BaseHTTPClient
  app AppServer.new

  def initialize
    super
    # Send JSON content-type for API requests
    # Browser actions should not be tested with this client
    headers("Content-Type": "application/json")
  end

  def self.auth(user : User)
    new.headers("Authorization": UserToken.generate(user))
  end
end
