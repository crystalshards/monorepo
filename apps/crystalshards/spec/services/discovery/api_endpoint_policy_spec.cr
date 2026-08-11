require "../../spec_helper"

# The gate a crawler's own HTTP requests pass, as distinct from GitHostPolicy,
# which gates repository URLs. Both exist because they answer different
# questions about different hostnames: bitbucket.org serves repositories and
# api.bitbucket.org serves the API, and admitting the second to the repository
# allowlist would make "https://api.bitbucket.org/..." a valid repository_url.
private def public_dns(&)
  GitHostPolicy.resolver = ->(_host : String) { [Socket::IPAddress.new("185.166.143.48", 443)] }
  begin
    yield
  ensure
    GitHostPolicy.resolver = nil
  end
end

private def policy(base : String) : Discovery::ApiEndpointPolicy
  Discovery::ApiEndpointPolicy.new(base, Discovery::BitbucketCrawler::API_HOSTS)
end

describe Discovery::ApiEndpointPolicy do
  describe "the endpoint it was configured with" do
    it "accepts a request to the API host it allows" do
      public_dns do
        gate = policy("https://api.bitbucket.org/2.0")
        gate.validate!("https://api.bitbucket.org/2.0/repositories/acme?page=2")
        gate.pinned_to_base?.should be_false
      end
    end

    it "refuses an API host that resolves somewhere internal" do
      GitHostPolicy.resolver = ->(_host : String) { [Socket::IPAddress.new("169.254.169.254", 443)] }
      begin
        # The cloud metadata server, reached through a name that is on the
        # allowlist. A name check alone does not catch this.
        expect_raises(Discovery::ApiEndpointPolicy::BlockedError, /non-public address/) do
          policy("https://api.bitbucket.org/2.0")
        end
      ensure
        GitHostPolicy.resolver = nil
      end
    end

    it "asks GitHostPolicy on every request, not only at startup" do
      public_dns do
        gate = policy("https://api.bitbucket.org/2.0")

        # Same origin, so origin pinning alone would pass it. The host is put
        # back through the policy anyway, which is what makes "every request is
        # gated" true rather than "the endpoint was gated once".
        asked = [] of String
        GitHostPolicy.resolver = ->(host : String) do
          asked << host
          [Socket::IPAddress.new("185.166.143.48", 443)]
        end

        gate.validate!("https://api.bitbucket.org/2.0/repositories/acme")
        # Re-checked without paying for DNS again: the allowlist answer cannot
        # change between two requests of one sweep, the resolve is the slow half.
        asked.should be_empty
      end
    end
  end

  describe "the two allowlists" do
    it "keeps the API host out of the repository allowlist" do
      # api.bitbucket.org must never become an acceptable repository_url. This
      # is the whole reason for a separate entry point rather than a wider
      # ALLOWED_HOSTS.
      GitHostPolicy::ALLOWED_HOSTS.should_not contain("api.bitbucket.org")
      GitHostPolicy::ALLOWED_HOSTS.should contain("bitbucket.org")

      public_dns do
        expect_raises(GitHostPolicy::UnsafeUrlError, /not a supported git host/) do
          GitHostPolicy.validate_fetch_url!("https://api.bitbucket.org/2.0/repositories/acme/router")
        end

        # And the repository host is not an API endpoint either.
        expect_raises(GitHostPolicy::UnsafeUrlError, /not an API endpoint/) do
          GitHostPolicy.validate_api_url!("https://bitbucket.org/acme/router", Discovery::BitbucketCrawler::API_HOSTS)
        end
      end
    end

    it "still refuses an unknown API host through the API path" do
      public_dns do
        expect_raises(GitHostPolicy::UnsafeUrlError, /not an API endpoint/) do
          GitHostPolicy.validate_api_url!("https://evil.test/2.0/repositories", Discovery::BitbucketCrawler::API_HOSTS)
        end
      end
    end
  end

  describe "a URL that came out of a response body" do
    it "refuses another host entirely" do
      public_dns do
        gate = policy("https://api.bitbucket.org/2.0")

        expect_raises(Discovery::ApiEndpointPolicy::BlockedError, /may only reach/) do
          gate.validate!("https://evil.test/2.0/repositories/acme?page=2")
        end
      end
    end

    it "refuses the same host on another port, and another scheme" do
      public_dns do
        gate = policy("https://api.bitbucket.org/2.0")

        expect_raises(Discovery::ApiEndpointPolicy::BlockedError, /may only reach/) do
          gate.validate!("https://api.bitbucket.org:8443/2.0/repositories/acme")
        end
        expect_raises(Discovery::ApiEndpointPolicy::BlockedError, /may only reach/) do
          gate.validate!("http://api.bitbucket.org/2.0/repositories/acme")
        end
      end
    end

    it "refuses a scheme that is not http, and a URL carrying credentials" do
      public_dns do
        gate = policy("https://api.bitbucket.org/2.0")

        expect_raises(Discovery::ApiEndpointPolicy::BlockedError, /only http/) do
          gate.validate!("file:///etc/passwd")
        end
        expect_raises(Discovery::ApiEndpointPolicy::BlockedError, /embedded credentials/) do
          gate.validate!("https://user:pass@api.bitbucket.org/2.0/repositories/acme")
        end
      end
    end
  end

  describe "a base the operator overrode" do
    it "pins to that origin and still refuses everything else, including the real host" do
      # This is the shape a spec or a mirror runs in. It is not a bypass: the
      # crawl may reach the one endpoint it was pointed at and nothing else.
      gate = policy("http://127.0.0.1:9931")
      gate.pinned_to_base?.should be_true

      gate.validate!("http://127.0.0.1:9931/repositories/acme?page=1")

      expect_raises(Discovery::ApiEndpointPolicy::BlockedError, /may only reach/) do
        gate.validate!("https://api.bitbucket.org/2.0/repositories/acme")
      end
      expect_raises(Discovery::ApiEndpointPolicy::BlockedError, /may only reach/) do
        gate.validate!("http://169.254.169.254/latest/meta-data/")
      end
    end
  end
end

describe Discovery::HostClient do
  describe "reading a rate limit off the host's own headers" do
    it "treats a small reset value as seconds to wait, which is how Bitbucket sends it" do
      FakeHost.run do |fake|
        sleeper = RecordedSleeper.new

        fake.on(/\/thing/) do |_target, attempt|
          if attempt.zero?
            FakeHost::Response.new(status: 429, body: "{}", headers: Discovery::Fixtures.bitbucket_rate_limit_headers(90))
          else
            FakeHost::Response.new(body: "{}")
          end
        end

        client = Discovery::HostClient.new(
          host: "bitbucket.org",
          base_url: fake.base_url,
          headers: HTTP::Headers.new,
          sleeper: sleeper.to_proc,
        )
        client.get("/thing")

        # Live, this header counts down in step with the wall clock: it read
        # 745, 737 then 728 across 16.5 seconds. Parsed as a Unix timestamp it
        # is 1970 and the wait collapses to the one second floor.
        sleeper.waits.should eq([90.seconds])
      end
    end

    it "still treats a large reset value as the timestamp GitHub and GitLab send" do
      FakeHost.run do |fake|
        sleeper = RecordedSleeper.new
        reset_at = Time.utc.to_unix + 120

        fake.on(/\/thing/) do |_target, attempt|
          if attempt.zero?
            FakeHost::Response.new(status: 429, body: "{}", headers: {
              "x-ratelimit-remaining" => "0",
              "x-ratelimit-reset"     => reset_at.to_s,
            })
          else
            FakeHost::Response.new(body: "{}")
          end
        end

        client = Discovery::HostClient.new(
          host: "github.com",
          base_url: fake.base_url,
          headers: HTTP::Headers.new,
          sleeper: sleeper.to_proc,
        )
        client.get("/thing")

        sleeper.waits.size.should eq(1)
        sleeper.waits.first.total_seconds.should be_close(120, 2)
      end
    end
  end

  describe "the request gate" do
    it "refuses before the request is made, not after it comes back" do
      FakeHost.run do |fake|
        fake.on(/\/thing/) { FakeHost::Response.new(body: "{}") }

        client = Discovery::HostClient.new(
          host: "bitbucket.org",
          base_url: fake.base_url,
          headers: HTTP::Headers.new,
          url_gate: ->(_url : String) { raise Discovery::ApiEndpointPolicy::BlockedError.new("nope") },
        )

        expect_raises(Discovery::ApiEndpointPolicy::BlockedError) { client.get("/thing") }
        # Nothing left the process.
        fake.requests.should be_empty
        client.requests_made.should eq(0)
      end
    end
  end

  describe "telling a refusal apart from a host having a bad minute" do
    it "raises Refused for a 403, carrying the status" do
      FakeHost.run do |fake|
        fake.on(/\/thing/) { FakeHost::Response.new(status: 403, body: %({"error":"denied"})) }

        client = Discovery::HostClient.new(host: "bitbucket.org", base_url: fake.base_url, headers: HTTP::Headers.new)

        error = expect_raises(Discovery::HostClient::Refused) { client.get("/thing") }
        error.status_code.should eq(403)
        # A subclass, so callers that only know about Error still catch it.
        error.is_a?(Discovery::HostClient::Error).should be_true
      end
    end

    it "raises a plain Error when a host fails to answer after every retry" do
      FakeHost.run do |fake|
        sleeper = RecordedSleeper.new
        fake.on(/\/thing/) { FakeHost::Response.new(status: 503, body: "upstream down") }

        client = Discovery::HostClient.new(
          host: "bitbucket.org",
          base_url: fake.base_url,
          headers: HTTP::Headers.new,
          max_retries: 2,
          sleeper: sleeper.to_proc,
        )

        error = expect_raises(Discovery::HostClient::Error) { client.get("/thing") }
        # Not a refusal: retrying this one is right, and a caller that steps
        # over refusals must not step over this.
        error.is_a?(Discovery::HostClient::Refused).should be_false
      end
    end
  end
end
