class ApiClient < Lucky::BaseHTTPClient
  app AppServer.new

  def initialize(*, skip_default_headers : Bool = false)
    super()
    unless skip_default_headers
      headers("Content-Type": "application/json")
    end
  end

  # Lucky's `headers` helper rewrites dashes to underscores, so it cannot send
  # a real header name like `X-GitHub-Event`. This sets them verbatim.
  def raw_headers(values : Hash(String, String)) : self
    client.before_request do |request|
      values.each { |name, value| request.headers[name] = value }
    end
    self
  end

  def self.auth(user : User)
    new.headers("Authorization": UserToken.generate(user))
  end

  def self.auth_multipart(user : User)
    new(skip_default_headers: true).headers("Authorization": UserToken.generate(user))
  end
end
