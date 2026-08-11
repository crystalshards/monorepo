require "uri"
require "../git_host_policy"

module Discovery
  # Pins a crawler to the endpoint it was configured with, and defers every
  # question about which hosts may be reached to GitHostPolicy.
  #
  # This is not a second gate. GitHostPolicy remains the one place that decides
  # whether a hostname may be contacted, and it grew a distinct entry point,
  # `validate_api_url!`, for API endpoints so that the crawlers' hostnames do
  # not have to be smuggled into the repository allowlist: bitbucket.org serves
  # repositories and api.bitbucket.org serves the API, and admitting the second
  # to ALLOWED_HOSTS would also make it an acceptable repository_url. What lives
  # here is the part GitHostPolicy has no opinion about, because it is about
  # configuration rather than safety:
  #
  #   origin pinning   a request may only go to the scheme, host and port this
  #                    crawler was configured with. Bitbucket pages with an
  #                    absolute `next` URL, so without this a response body is a
  #                    redirect primitive: it could name a host that is itself
  #                    perfectly allowlisted and still not the one this crawl is
  #                    supposed to be reading.
  #
  # The endpoint is admitted once, at construction, with a full DNS and
  # public-address check. Every subsequent request is re-checked against
  # GitHostPolicy without the resolve, since the answer to "is this host
  # allowed" cannot change between two requests of one sweep and the resolve is
  # the expensive half.
  #
  # `pinned_to_base` is the mode an operator gets by overriding the base URL,
  # which is how the specs point a crawler at a local server and how a mirror
  # would be configured. It is chosen by configuration and never by anything a
  # response said. Origin pinning still applies underneath it, so a crawler
  # pointed at 127.0.0.1 may talk to that one port and nothing else, including
  # the real Bitbucket.
  class ApiEndpointPolicy
    class BlockedError < Exception
    end

    getter origin : String
    getter allowed_hosts : Array(String)
    getter? pinned_to_base : Bool

    def initialize(base_url : String, @allowed_hosts : Array(String))
      uri = parse(base_url)
      host = host_of(uri, base_url)
      @origin = origin_of(uri, host)
      @pinned_to_base = !@allowed_hosts.includes?(host)

      # Fail before the first request rather than on whichever page happens to
      # be first. A base that resolves somewhere internal is refused here.
      unless @pinned_to_base
        admit!(base_url, resolve_dns: true)
      end
    end

    # Raises BlockedError unless this exact URL may be requested.
    def validate!(url : String) : Nil
      uri = parse(url)

      scheme = uri.scheme.try(&.downcase)
      unless scheme == "http" || scheme == "https"
        raise BlockedError.new("#{url.inspect} refused: only http:// and https:// may be requested")
      end

      if uri.user || uri.password
        raise BlockedError.new("#{url.inspect} refused: URLs carrying embedded credentials may not be requested")
      end

      actual = origin_of(uri, host_of(uri, url))

      unless actual == origin
        raise BlockedError.new(
          "#{url.inspect} refused: this crawl may only reach #{origin}, and that URL points at #{actual}. " \
          "A cursor or link in a response cannot move the crawl to another host."
        )
      end

      # Same origin as a base that was admitted at construction, so the host is
      # already known good. Asked again anyway, because "the gate ran once at
      # startup" is a weaker statement than "the gate ran on this request".
      admit!(url, resolve_dns: false) unless pinned_to_base?
    end

    private def admit!(url : String, resolve_dns : Bool)
      GitHostPolicy.validate_api_url!(url, allowed_hosts, resolve_dns: resolve_dns)
    rescue ex : GitHostPolicy::UnsafeUrlError
      raise BlockedError.new(ex.message)
    end

    private def parse(url : String) : URI
      URI.parse(url)
    rescue ex : URI::Error
      raise BlockedError.new("#{url.inspect} refused: not a parseable URL (#{ex.message})")
    end

    private def host_of(uri : URI, url : String) : String
      host = uri.host
      if host.nil? || host.empty?
        raise BlockedError.new("#{url.inspect} refused: URL has no host")
      end

      host.strip.downcase.lchop('[').rchop(']').rchop('.')
    end

    private def origin_of(uri : URI, host : String) : String
      scheme = uri.scheme.try(&.downcase) || "https"
      port = uri.port || (scheme == "https" ? 443 : 80)
      "#{scheme}://#{host}:#{port}"
    end
  end
end
