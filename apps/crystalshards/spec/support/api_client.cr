class ApiClient < Lucky::BaseHTTPClient
  app AppServer.new

  def initialize(*, skip_default_headers : Bool = false, json_content : Bool = false)
    super()
    unless skip_default_headers
      # Only set JSON content-type when explicitly needed for API endpoints
      # This allows testing both Browser actions (HTML) and API actions (JSON)
      headers("Content-Type": "application/json") if json_content
    end
  end

  def self.auth(user : User, json: Bool = false)
    new(json_content: json).headers("Authorization": UserToken.generate(user))
  end

  def self.auth_multipart(user : User)
    new(skip_default_headers: true).headers("Authorization": UserToken.generate(user))
  end
end
