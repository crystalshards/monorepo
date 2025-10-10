class ApiClient < Lucky::BaseHTTPClient
  app AppServer.new

  # Note: Not setting Content-Type header to allow testing both
  # API actions (which accept JSON) and Browser actions (which accept HTML)
  # Lucky will handle the format negotiation based on the action's accepted_formats

  def self.auth(user : User)
    new.headers("Authorization": UserToken.generate(user))
  end
end
