require "uri"
require "socket"

# GitHostPolicy is the single gate a URL must pass before the registry points a
# provider, clone, probe, or HTTP fetch at it.
#
# Without it, `repository_url` is an SSRF primitive: anything reaching
# `ProviderFactory.create` or a provider's clone becomes a request originating
# inside our own network, with whatever the pod can reach. On GCP that includes
# 169.254.169.254, which hands out credentials.
#
# Two layers, because either alone is bypassable:
#
#   1. An allowlist of known public git hosts. Unknown hosts are refused, which
#      also disposes of decimal/hex/octal IP literals ("http://2130706433/"),
#      lookalike domains ("github.com.evil.test") and self-hosted endpoints we
#      have no crawler for anyway.
#   2. DNS resolution of the hostname, with every returned address checked
#      against loopback, RFC1918, link-local, CGNAT and other non-public
#      ranges. A string check alone lets a DNS name that points at an internal
#      address walk straight through.
#
# Residual risk, stated plainly: validation resolves the name, then the HTTP
# client or git resolves it again when it connects, so a name whose DNS answer
# flips between those two moments is not excluded by resolution alone. The
# allowlist is what closes that in practice, since an attacker does not control
# DNS for github.com, gitlab.com, bitbucket.org or codeberg.org, and TLS
# authenticates the endpoint on every https fetch.
class GitHostPolicy
  class UnsafeUrlError < Exception
  end

  # Hosts the registry knows how to crawl and fetch from. Deliberately exact:
  # no suffix matching, because "github.com.evil.test" and "evilgithub.com"
  # both satisfy a naive `ends_with?`/`includes?` test.
  ALLOWED_HOSTS = %w[
    github.com
    gitlab.com
    bitbucket.org
    codeberg.org
  ]

  alias Resolver = Proc(String, Array(Socket::IPAddress))

  @@resolver : Resolver? = nil

  # Test seam. Production never assigns this. Specs use it to prove a hostname
  # resolving to a private address is refused, without needing a real DNS entry
  # that points somewhere internal.
  def self.resolver=(resolver : Resolver?)
    @@resolver = resolver
  end

  def self.resolver : Resolver?
    @@resolver
  end

  # Returns the parsed URI when the URL is safe to fetch, raises otherwise.
  def self.validate_fetch_url!(url : String) : URI
    admit!(normalize_url(url), url, ALLOWED_HOSTS, "a supported git host", resolve_dns: true)
  end

  # The same gate, for the API endpoints the crawlers talk to rather than the
  # repository hosts they store.
  #
  # A separate entry point with a caller-supplied allowlist, because the two
  # answer different questions about different hostnames. bitbucket.org serves
  # repositories and api.bitbucket.org serves the API; folding the second into
  # ALLOWED_HOSTS would also make "https://api.bitbucket.org/..." an acceptable
  # repository_url, which it is not. What they share, and what this keeps in one
  # place, is the scheme, credential, IP-literal, DNS and public-address
  # checking: a second implementation of those is a second thing to get wrong.
  #
  # `resolve_dns` is false for the per-request check on a hot path, where the
  # endpoint was already resolved and range-checked when the crawler was built
  # and the question is only whether this URL still names it.
  def self.validate_api_url!(url : String, allowed_hosts : Array(String), resolve_dns : Bool = true) : URI
    admit!(url, url, allowed_hosts, "an API endpoint this registry talks to", resolve_dns: resolve_dns)
  end

  private def self.admit!(
    candidate : String,
    url : String,
    allowed_hosts : Array(String),
    description : String,
    resolve_dns : Bool,
  ) : URI
    uri = parse_uri(candidate)

    scheme = uri.scheme.try(&.downcase)
    unless scheme == "http" || scheme == "https"
      raise UnsafeUrlError.new("#{url.inspect} rejected: only http:// and https:// URLs may be fetched")
    end

    if uri.user || uri.password
      raise UnsafeUrlError.new("#{url.inspect} rejected: URLs carrying embedded credentials may not be fetched")
    end

    host = uri.host
    if host.nil? || host.empty?
      raise UnsafeUrlError.new("#{url.inspect} rejected: URL has no host")
    end

    host = canonical_host(host)

    if literal = ip_literal(host)
      # An IP literal can never be an allowlisted host. Range-check it anyway so
      # the log names the boundary that was crossed instead of a flat refusal.
      unless public_address?(literal)
        raise UnsafeUrlError.new("#{url.inspect} rejected: #{literal.address} is a loopback, private, link-local or otherwise non-public address")
      end
      raise UnsafeUrlError.new("#{url.inspect} rejected: bare IP addresses are not accepted as repository hosts")
    end

    unless allowed_hosts.includes?(host)
      raise UnsafeUrlError.new("#{url.inspect} rejected: #{host} is not #{description} (#{allowed_hosts.join(", ")})")
    end

    return uri unless resolve_dns

    addresses = resolve(host, url)
    if addresses.empty?
      raise UnsafeUrlError.new("#{url.inspect} rejected: #{host} did not resolve to any address")
    end

    addresses.each do |address|
      next if public_address?(address)
      raise UnsafeUrlError.new("#{url.inspect} rejected: #{host} resolves to #{address.address}, a loopback, private, link-local or otherwise non-public address")
    end

    uri
  end

  def self.safe_fetch_url?(url : String) : Bool
    validate_fetch_url!(url)
    true
  rescue UnsafeUrlError
    false
  end

  # scp-style remotes ("git@github.com:owner/repo.git") are the one non-URL
  # spelling the registry has always accepted. Rewrite them to https for
  # allowlisted hosts so everything downstream deals with a single parseable
  # shape, and leave anything else alone so the checks above reject it.
  def self.normalize_url(url : String) : String
    stripped = url.strip
    if match = stripped.match(/\Agit@([A-Za-z0-9.\-]+):(.+)\z/)
      host = canonical_host(match[1])
      return "https://#{host}/#{match[2].lstrip('/')}" if ALLOWED_HOSTS.includes?(host)
    end
    stripped
  end

  private def self.parse_uri(url : String) : URI
    URI.parse(url)
  rescue ex : URI::Error
    raise UnsafeUrlError.new("#{url.inspect} rejected: not a parseable URL (#{ex.message})")
  end

  private def self.canonical_host(host : String) : String
    host = host.strip.downcase
    host = host.lchop('[').rchop(']')
    while host.ends_with?('.')
      host = host.rchop('.')
    end
    host = host.lchop("www.") if host.starts_with?("www.")
    host
  end

  private def self.resolve(host : String, url : String) : Array(Socket::IPAddress)
    if resolver = @@resolver
      resolver.call(host)
    else
      Socket::Addrinfo.resolve(host, "https", type: Socket::Type::STREAM).map(&.ip_address)
    end
  rescue ex : Socket::Error
    raise UnsafeUrlError.new("#{url.inspect} rejected: could not resolve #{host} (#{ex.message})")
  end

  private def self.ip_literal(host : String) : Socket::IPAddress?
    return nil unless host.matches?(/\A[0-9.]+\z/) || host.includes?(':')
    Socket::IPAddress.new(host, 0)
  rescue Socket::Error
    # Something shaped like a literal that does not parse as one is not a
    # hostname either. The allowlist check refuses it on the next line.
    nil
  end

  def self.public_address?(address : Socket::IPAddress) : Bool
    case address.family
    when Socket::Family::INET
      if v4 = parse_ipv4(address.address)
        public_ipv4?(v4)
      else
        false
      end
    when Socket::Family::INET6
      if bytes = parse_ipv6(address.address)
        public_ipv6?(bytes)
      else
        false
      end
    else
      false
    end
  end

  private def self.public_ipv4?(v4 : UInt32) : Bool
    a = (v4 >> 24).to_u8
    b = ((v4 >> 16) & 0xff).to_u8
    c = ((v4 >> 8) & 0xff).to_u8

    return false if a == 0                             # 0.0.0.0/8 this network
    return false if a == 10                            # RFC1918
    return false if a == 127                           # loopback
    return false if a == 100 && (64..127).includes?(b) # CGNAT 100.64.0.0/10
    return false if a == 169 && b == 254               # link-local, cloud metadata
    return false if a == 172 && (16..31).includes?(b)  # RFC1918
    return false if a == 192 && b == 168               # RFC1918
    return false if a == 192 && b == 0 && c == 0       # IETF protocol assignments
    return false if a == 192 && b == 0 && c == 2       # TEST-NET-1
    return false if a == 198 && (18..19).includes?(b)  # benchmarking
    return false if a == 198 && b == 51 && c == 100    # TEST-NET-2
    return false if a == 203 && b == 0 && c == 113     # TEST-NET-3
    return false if a >= 224                           # multicast and reserved

    true
  end

  private def self.public_ipv6?(bytes : Bytes) : Bool
    return false if bytes.all?(&.zero?)                                                          # ::
    return false if bytes[0, 15].all?(&.zero?) && bytes[15] == 1                                 # ::1
    return false if bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80                                # fe80::/10
    return false if (bytes[0] & 0xfe) == 0xfc                                                    # fc00::/7 ULA
    return false if bytes[0] == 0xff                                                             # ff00::/8 multicast
    return false if bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x0d && bytes[3] == 0xb8 # 2001:db8::/32

    # ::ffff:0:0/96 IPv4-mapped and 64:ff9b::/96 NAT64 both carry a v4 address
    # in the last four bytes. Without this, ::ffff:169.254.169.254 reaches the
    # metadata server through an IPv6 literal.
    if mapped = mapped_ipv4(bytes)
      return public_ipv4?(mapped)
    end

    true
  end

  private def self.mapped_ipv4(bytes : Bytes) : UInt32?
    v4_mapped = bytes[0, 10].all?(&.zero?) && bytes[10] == 0xff && bytes[11] == 0xff
    nat64 = bytes[0] == 0x00 && bytes[1] == 0x64 && bytes[2] == 0xff && bytes[3] == 0x9b &&
            bytes[4, 8].all?(&.zero?)

    return nil unless v4_mapped || nat64

    (bytes[12].to_u32 << 24) | (bytes[13].to_u32 << 16) | (bytes[14].to_u32 << 8) | bytes[15].to_u32
  end

  private def self.parse_ipv4(address : String) : UInt32?
    parts = address.split('.')
    return nil unless parts.size == 4

    value = 0_u32
    parts.each do |part|
      return nil if part.empty? || part.size > 3
      return nil unless part.each_char.all?(&.ascii_number?)
      octet = part.to_u32?
      return nil unless octet && octet <= 255
      value = (value << 8) | octet
    end
    value
  end

  private def self.parse_ipv6(address : String) : Bytes?
    text = address.downcase
    text = text[0, text.index('%') || text.size] # drop any zone id

    halves = text.split("::")
    return nil if halves.size > 2

    if halves.size == 2
      left = expand_groups(halves[0])
      right = expand_groups(halves[1])
      return nil unless left && right

      fill = 8 - left.size - right.size
      return nil if fill < 1

      words = left + Array(UInt16).new(fill, 0_u16) + right
    else
      groups = expand_groups(text)
      return nil unless groups
      words = groups
    end

    return nil unless words.size == 8

    bytes = Bytes.new(16)
    words.each_with_index do |word, index|
      bytes[index * 2] = (word >> 8).to_u8
      bytes[index * 2 + 1] = (word & 0xff).to_u8
    end
    bytes
  end

  # Turns one side of an IPv6 address into 16-bit words. A trailing dotted quad
  # ("::ffff:127.0.0.1") expands into the two words it occupies.
  private def self.expand_groups(text : String) : Array(UInt16)?
    return [] of UInt16 if text.empty?

    parts = text.split(':')
    words = [] of UInt16

    parts.each_with_index do |part, index|
      return nil if part.empty?

      if part.includes?('.')
        return nil unless index == parts.size - 1
        v4 = parse_ipv4(part)
        return nil unless v4
        words << ((v4 >> 16) & 0xffff).to_u16
        words << (v4 & 0xffff).to_u16
      else
        return nil if part.size > 4
        return nil unless part.each_char.all? { |char| char.ascii_number? || ('a'..'f').includes?(char) }
        word = part.to_u16?(16)
        return nil unless word
        words << word
      end
    end

    words
  end
end
