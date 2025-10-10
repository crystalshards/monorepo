class BrowserClient < Lucky::BaseHTTPClient
  app AppServer.new

  def initialize
    super
    # Request HTML format for BrowserActions
    headers("Accept": "text/html")
  end

  # Override exec to send form-encoded data instead of JSON
  def exec(action : Lucky::Action.class, **params) : HTTP::Client::Response
    exec(action.route, params)
  end

  def exec(route_helper : Lucky::RouteHelper, **params) : HTTP::Client::Response
    exec(route_helper, params)
  end

  def exec(action : Lucky::Action.class, params : NamedTuple) : HTTP::Client::Response
    exec(action.route, **params)
  end

  def exec(route_helper : Lucky::RouteHelper, params : NamedTuple) : HTTP::Client::Response
    # Convert nested params to form-encoded data instead of JSON
    form_data = encode_form_params(params)
    headers(content_type: "application/x-www-form-urlencoded").exec_raw(route_helper, form_data)
  end

  private def encode_form_params(params : NamedTuple) : String
    URI::Params.build do |builder|
      flatten_params(params).each do |key, value|
        builder.add(key, value)
      end
    end
  end

  private def flatten_params(params : NamedTuple, prefix : String? = nil) : Hash(String, String)
    result = {} of String => String
    params.each do |key, value|
      full_key = prefix ? "#{prefix}[#{key}]" : key.to_s
      case value
      when NamedTuple, Hash
        result.merge!(flatten_params(value, full_key))
      when Array
        value.each_with_index do |item, index|
          case item
          when NamedTuple, Hash
            result.merge!(flatten_params(item, "#{full_key}[#{index}]"))
          else
            result["#{full_key}[#{index}]"] = item.to_s
          end
        end
      else
        result[full_key] = value.to_s
      end
    end
    result
  end

  # BrowserClient for testing BrowserActions (HTML format)
  # Use ApiClient for testing API endpoints
end
