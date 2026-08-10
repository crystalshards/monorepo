class AppClient < Lucky::BaseHTTPClient
  app AppServer.new

  def initialize
    super
  end
end
