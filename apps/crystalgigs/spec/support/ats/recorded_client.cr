# An `Ats::Client` that replays recorded payloads instead of making requests.
#
# Specs never call a live ATS. Every response here comes from a fixture that
# was captured from the provider's real public endpoint, or from a status code
# we want to see handled. An unstubbed URL raises rather than falling through
# to the network, so a spec cannot accidentally start making real requests.
class RecordedAtsClient < CrystalGigs::Ats::Client
  record RecordedRequest,
    method : String,
    url : String,
    headers : HTTP::Headers,
    body : String?

  getter requests = [] of RecordedRequest

  def initialize
    @stubs = [] of {String, String, CrystalGigs::Ats::Response}
  end

  # Stubs are matched by substring, in registration order, so a URL carrying a
  # query string (Lever puts its API key there) still matches. Re-stubbing the
  # same fragment replaces the previous answer, which is how a spec models a
  # board changing between two syncs.
  def stub(method : String, url_fragment : String, body : String, status : Int32 = 200) : Nil
    entry = {method.upcase, url_fragment, CrystalGigs::Ats::Response.new(status, body)}
    index = @stubs.index { |(stub_method, fragment, _)| stub_method == entry[0] && fragment == url_fragment }

    if index
      @stubs[index] = entry
    else
      @stubs << entry
    end
  end

  def stub_get(url_fragment : String, body : String, status : Int32 = 200) : Nil
    stub("GET", url_fragment, body, status)
  end

  def stub_post(url_fragment : String, body : String, status : Int32 = 200) : Nil
    stub("POST", url_fragment, body, status)
  end

  def get(url : String, headers : HTTP::Headers) : CrystalGigs::Ats::Response
    @requests << RecordedRequest.new("GET", url, headers, nil)
    respond("GET", url)
  end

  def post(url : String, headers : HTTP::Headers, body : String) : CrystalGigs::Ats::Response
    @requests << RecordedRequest.new("POST", url, headers, body)
    respond("POST", url)
  end

  def last_request : RecordedRequest
    @requests.last
  end

  def posted_bodies : Array(String)
    @requests.select(&.method.== "POST").compact_map(&.body)
  end

  private def respond(method : String, url : String) : CrystalGigs::Ats::Response
    match = @stubs.find do |(stub_method, fragment, _)|
      stub_method == method && url.includes?(fragment)
    end

    raise "RecordedAtsClient has no stub for #{method} #{url}" if match.nil?

    match[2]
  end
end
