require "../spec_helper"
require "http/server"

# The component specs stub the transport, which is right for testing rendering
# rules and wrong for testing the thing that will actually break in production:
# a real socket talking to a real CrystalBits that is slow, angry or wrong.
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

  CrystalShards::BitsFeed.origin = "http://#{address}"
  CrystalShards::BitsFeed.transport = nil
  CrystalShards::BitsFeed.reset!

  begin
    yield address
  ensure
    server.close
    CrystalShards::BitsFeed.origin = nil
    CrystalShards::BitsFeed.reset!
  end
end

private FEED = <<-JSON
  {"posts":[
    {"title":"Why Crystal","slug":"why-crystal","excerpt":"A short excerpt."}
  ]}
  JSON

describe CrystalShards::BitsFeed do
  describe "the real HTTP path" do
    it "renders the feed a healthy CrystalBits serves" do
      with_server(->(context : HTTP::Server::Context) {
        context.response.content_type = "application/json"
        context.response.print FEED
      }) do |address|
        articles = CrystalShards::BitsFeed.current(3)

        articles.size.should eq(1)
        articles.first.title.should eq("Why Crystal")
        CrystalShards::BitsFeed.article_url("http://#{address}", articles.first)
          .should eq("http://#{address}/posts/why-crystal")
      end
    end

    it "asks the feed for exactly the three articles the strip shows" do
      requested = Channel(String).new

      with_server(->(context : HTTP::Server::Context) {
        requested.send(context.request.resource)
        context.response.content_type = "application/json"
        context.response.print FEED
      }) do
        CrystalShards::BitsFeed.current(3)

        requested.receive.should eq("/api/posts?per_page=3")
      end
    end

    it "renders nothing when CrystalBits answers with an error" do
      with_server(->(context : HTTP::Server::Context) {
        context.response.status = :internal_server_error
        context.response.print %({"posts":[{"title":"Leaked","slug":"leaked"}]})
      }) do
        # A 500 whose body happens to parse must not render. The status is the
        # answer, not the payload.
        CrystalShards::BitsFeed.current(3).should be_empty
      end
    end

    it "gives up on a CrystalBits that never answers, instead of holding the page" do
      with_server(->(context : HTTP::Server::Context) {
        # Far longer than READ_TIMEOUT. Without a timeout this is the failure
        # that hangs every page render on three sites.
        sleep 5.seconds
        context.response.print FEED
      }) do
        started = Time.monotonic
        articles = CrystalShards::BitsFeed.current(3)
        elapsed = Time.monotonic - started

        articles.should be_empty
        # The budget is CONNECT_TIMEOUT + READ_TIMEOUT, with room for a loaded
        # machine. The claim is that it returns bounded, not that it returns at
        # an exact moment.
        elapsed.should be < 3.seconds
      end
    end

    it "renders nothing when the response is too large to be our feed" do
      oversized = %({"posts":[) +
                  Array.new(400) do |i|
                    %({"title":"#{"padding " * 20}#{i}","slug":"post-#{i}"})
                  end.join(",") + "]}"
      oversized.bytesize.should be > CrystalShards::BitsFeed::MAX_BODY_BYTES

      with_server(->(context : HTTP::Server::Context) {
        context.response.content_type = "application/json"
        context.response.print oversized
      }) do
        CrystalShards::BitsFeed.current(3).should be_empty
      end
    end

    it "renders nothing when nothing is listening on the configured origin" do
      # Bind a port to learn a free number, then close it, so the address is
      # one that nothing answers on.
      vacated = HTTP::Server.new { }
      address = vacated.bind_unused_port
      vacated.close

      CrystalShards::BitsFeed.origin = "http://#{address}"
      CrystalShards::BitsFeed.transport = nil
      CrystalShards::BitsFeed.reset!

      begin
        CrystalShards::BitsFeed.current(3).should be_empty
      ensure
        CrystalShards::BitsFeed.origin = nil
        CrystalShards::BitsFeed.reset!
      end
    end
  end
end
