class ApiClient < Lucky::BaseHTTPClient
  app AppServer.new

  def initialize(*, skip_default_headers : Bool = false)
    super()
    unless skip_default_headers
      headers("Content-Type": "application/json")
    end
  end

  def self.auth(user : User)
    new.headers("Authorization": UserToken.generate(user))
  end

  def self.auth_multipart(user : User)
    new(skip_default_headers: true).headers("Authorization": UserToken.generate(user))
  end
end
