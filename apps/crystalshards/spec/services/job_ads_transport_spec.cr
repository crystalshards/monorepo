require "../spec_helper"
require "http/server"

# The component specs stub the transport, which is right for testing rendering
# rules and wrong for testing the thing that will actually break in production:
# a real socket talking to a real CrystalGigs that is slow, angry or wrong.
# These examples run the unstubbed HTTP path against a real server.
private alias Handler = HTTP::Server::Context -> Nil

private def with_server(handler : Handler, &)
  server = HTTP::Server.new do |context|
    # A handler that raises after the client has walked away is normal here.
    # It must not take the spec run down with it.
    handler.call(context) rescue nil
  end
  address = server.bind_unused_port
  spawn { server.listen }
  # Let the accept loop have a turn before anything connects to it.
  Fiber.yield

  CrystalShards::JobAdsConfig.endpoint = URI.parse("http://#{address}/api/ads")
  CrystalShards::JobAds.transport = nil
  CrystalShards::JobAds.reset!

  begin
    yield
  ensure
    server.close
    CrystalShards::JobAdsConfig.endpoint = nil
    CrystalShards::JobAds.reset!
  end
end

private FEED = <<-JSON
  {"jobs":[
    {"title":"Senior Crystal Developer","company":"Crystal Corp","location":"Denver, CO",
     "remote":true,"featured":true,"url":"https://crystalgigs.test/jobs/7"}
  ]}
  JSON

describe CrystalShards::JobAds do
  describe "the real HTTP path" do
    it "renders the feed a healthy CrystalGigs serves" do
      with_server(->(context : HTTP::Server::Context) {
        context.response.content_type = "application/json"
        context.response.print FEED
      }) do
        ads = CrystalShards::JobAds.current(3)

        ads.size.should eq(1)
        ads.first.title.should eq("Senior Crystal Developer")
        ads.first.featured?.should be_true
        ads.first.remote?.should be_true
      end
    end

    it "renders nothing when CrystalGigs answers with an error" do
      with_server(->(context : HTTP::Server::Context) {
        context.response.status = :internal_server_error
        context.response.print %({"jobs":[{"title":"Leaked","company":"X","url":"https://x.test/1"}]})
      }) do
        # A 500 whose body happens to parse must not render. The status is the
        # answer, not the payload.
        CrystalShards::JobAds.current(3).should be_empty
      end
    end

    it "gives up on a CrystalGigs that never answers, instead of holding the page" do
      with_server(->(context : HTTP::Server::Context) {
        # Far longer than READ_TIMEOUT. Without a timeout this is the failure
        # that hangs every page render on three sites.
        sleep 5.seconds
        context.response.print FEED
      }) do
        started = Time.monotonic
        ads = CrystalShards::JobAds.current(3)
        elapsed = Time.monotonic - started

        ads.should be_empty
        # The budget is CONNECT_TIMEOUT + READ_TIMEOUT, with room for a loaded
        # machine. The claim is that it returns bounded, not that it returns at
        # an exact moment.
        elapsed.should be < 3.seconds
      end
    end

    it "renders nothing when the response is too large to be our feed" do
      oversized = %({"jobs":[) +
                  Array.new(400) do |i|
                    %({"title":"#{"padding " * 20}#{i}","company":"C","url":"https://x.test/#{i}"})
                  end.join(",") + "]}"
      oversized.bytesize.should be > CrystalShards::JobAds::MAX_BODY_BYTES

      with_server(->(context : HTTP::Server::Context) {
        context.response.content_type = "application/json"
        context.response.print oversized
      }) do
        CrystalShards::JobAds.current(3).should be_empty
      end
    end

    it "renders nothing when nothing is listening on the configured endpoint" do
      # Bind a port to learn a free number, then close it, so the address is
      # one that nothing answers on.
      vacated = HTTP::Server.new { }
      address = vacated.bind_unused_port
      vacated.close

      CrystalShards::JobAdsConfig.endpoint = URI.parse("http://#{address}/api/ads")
      CrystalShards::JobAds.transport = nil
      CrystalShards::JobAds.reset!

      begin
        CrystalShards::JobAds.current(3).should be_empty
      ensure
        CrystalShards::JobAdsConfig.endpoint = nil
        CrystalShards::JobAds.reset!
      end
    end
  end
end
