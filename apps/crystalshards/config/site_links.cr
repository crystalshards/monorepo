require "uri"

# Where the other Bushido Collective sites answer, read from configuration so
# a footer's cross links are built from real origins and never point at
# another environment's copy of a site. The same problem
# `CrystalShards::DocsSite` solves for one origin, generalized to all four
# public sites so a footer never composes a URL from a bare hostname.
#
# This file is intentionally identical in every app, the same way
# config/object_store.cr is: the apps build as independent images with
# apps/<app> as the docker context, so a shared module has no home to live
# in, and keeping the four copies byte-identical makes drift a one-line
# `cmp` instead of a merge.
module SiteLinks
  # One entry per public site: the env var that holds its origin, and the
  # name and one-line description a footer shows when it links there.
  record Site, env_key : String, name : String, description : String

  # A Hash, not a NamedTuple: `origin` and `others` both look a site up by a
  # runtime Symbol, and a NamedTuple only indexes by a literal known at
  # compile time. Insertion order is preserved, so this is also the order a
  # footer lists the other three sites in.
  SITES = {
    :crystalshards => Site.new("SHARDS_SITE_ORIGIN", "CrystalShards", "The Crystal shard registry"),
    :crystaldocs   => Site.new("DOCS_SITE_ORIGIN", "CrystalDocs", "Generated documentation for indexed shards"),
    :crystalgigs   => Site.new("GIGS_SITE_ORIGIN", "CrystalGigs", "Job board for Crystal developers"),
    :crystalbits   => Site.new("BITS_SITE_ORIGIN", "CrystalBits", "News and tutorials from the Crystal community"),
  } of Symbol => Site

  # A site origin is a deployment fact, the same way DOCS_SITE_ORIGIN already
  # is in CrystalShards::DocsSite: no default, because a guess about where
  # another service lives produces a link that resolves somewhere real, which
  # is the failure nobody notices. A blank footer link would at least be
  # visibly broken; a wrong one is not.
  class MissingOrigin < Exception
    def initialize(env_key : String)
      super(
        "#{env_key} is not set. It is the origin a Bushido Collective site " \
        "answers on, for example https://crystaldocs.org in production or " \
        "http://localhost:3001 against the local stack. Every footer cross " \
        "link this app renders is built from it, so there is no value that " \
        "could be guessed that would not be wrong somewhere."
      )
    end
  end

  # A value that is set but is not an origin. CrystalShards::DocsSite hit
  # this in production when terraform composed a scheme onto a value that
  # was already a full origin; the same composition mistake is possible here
  # with four variables instead of one, so it is guarded the same way.
  class MalformedOrigin < Exception
    def initialize(env_key : String, raw : String, reason : String)
      super(
        "#{env_key} is #{raw.inspect}, which #{reason}. It must be a scheme " \
        "and host with no path, for example https://crystaldocs.org."
      )
    end
  end

  # The origin for one site, or raised for the reasons above.
  def self.origin(site : Symbol) : String
    entry = SITES[site]? || raise ArgumentError.new("SiteLinks knows nothing about #{site}")
    resolve(entry.env_key)
  end

  # The other three sites, in SITES' declared order, for a footer to render
  # as cross links. Excludes only the caller's own site, so the same table
  # serves every app without four different three-key copies of it.
  def self.others(than site : Symbol) : Array(Symbol)
    SITES.keys.reject { |key| key == site }
  end

  # Force resolution of every site's origin, so a missing or malformed one is
  # a startup failure naming the variable rather than a footer link a reader
  # actually clicks on. Called unconditionally in production only, at the
  # bottom of this file.
  def self.require! : Nil
    SITES.each_key { |site| origin(site) }
  end

  private def self.resolve(env_key : String) : String
    raw = ENV[env_key]?
    raise MissingOrigin.new(env_key) if raw.nil? || raw.blank?

    value = raw.strip.rstrip('/')
    uri = URI.parse(value)

    raise MalformedOrigin.new(env_key, value, "has no scheme") if uri.scheme.nil?
    unless {"http", "https"}.includes?(uri.scheme)
      raise MalformedOrigin.new(env_key, value, "is not http or https")
    end
    raise MalformedOrigin.new(env_key, value, "has no host") if uri.host.nil? || uri.host.try(&.blank?)
    raise MalformedOrigin.new(env_key, value, "has a path") unless uri.path.blank?

    value
  end
end

# Production only, the same way `CrystalStorage::Buckets.require!` is guarded
# in object_store_buckets.cr: in development and test the four origins are
# docker-compose's and CI's own localhost values, wired the same way
# DOCS_SITE_ORIGIN already is, so nothing here needs a fallback default.
SiteLinks.require! if LuckyEnv.production?
