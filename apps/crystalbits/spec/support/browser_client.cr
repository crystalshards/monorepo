class BrowserClient < Lucky::BaseHTTPClient
  app AppServer.new

  FORM_CONTENT_TYPE = "application/x-www-form-urlencoded"

  def initialize
    super
    # Request HTML format for BrowserActions
    headers("Accept": "text/html")
  end

  # BrowserClient for testing BrowserActions (HTML format)
  # Use ApiClient for testing API endpoints
  #
  # Lucky::BaseHTTPClient#exec serializes params into a JSON body, which a
  # BrowserAction never reads: it parses form-encoded bodies and query strings.
  # Encode params the way a browser does instead. Nested params use Lucky's
  # `parent:child` key convention, which is what Avram operations expect from
  # their param_key.
  def exec(action : Lucky::Action.class, **params) : HTTP::Client::Response
    exec(action.route, params)
  end

  def exec(route_helper : Lucky::RouteHelper, **params) : HTTP::Client::Response
    exec(route_helper, params)
  end

  def exec(action : Lucky::Action.class, params : NamedTuple) : HTTP::Client::Response
    exec(action.route, params)
  end

  def exec(route_helper : Lucky::RouteHelper, params : NamedTuple) : HTTP::Client::Response
    method = route_helper.method.to_s.upcase
    encoded = encode_params(params)

    if method == "GET" || method == "HEAD"
      client.exec(method: method, path: with_query(route_helper.path, encoded))
    else
      client.exec(
        method: method,
        path: route_helper.path,
        headers: HTTP::Headers{"Content-Type" => FORM_CONTENT_TYPE},
        body: encoded
      )
    end
  end

  private def encode_params(params : NamedTuple) : String
    URI::Params.build do |form|
      params.each do |key, value|
        add_param(form, key.to_s, value)
      end
    end
  end

  private def add_param(form : URI::Params::Builder, key : String, value : NamedTuple) : Nil
    value.each do |nested_key, nested_value|
      add_param(form, "#{key}:#{nested_key}", nested_value)
    end
  end

  private def add_param(form : URI::Params::Builder, key : String, value) : Nil
    form.add(key, value.to_s)
  end

  private def with_query(path : String, query : String) : String
    return path if query.empty?

    separator = path.includes?('?') ? '&' : '?'
    "#{path}#{separator}#{query}"
  end
end
