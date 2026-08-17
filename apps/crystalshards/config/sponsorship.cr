require "uri"

# Where a reader who wants to help pay for this site is sent, read from
# configuration because the destination is a deployment decision, not a code
# decision: the owner has not yet chosen between the collective's existing
# sponsorship page and a GitHub Sponsors profile, and the answer can differ
# per deploy until it is made.
#
# Unset is a legitimate state in every environment, production included: it
# means "not open for sponsorship yet", and the /sponsor page says so plainly
# instead of rendering a dead button. A value that IS set has to be an
# absolute http(s) URL, because that button is the only thing the value is
# for, and a malformed one would otherwise fail at click time in a reader's
# browser instead of at boot with the variable named.
#
# This file is intentionally identical in every app, the same way
# config/site_links.cr is: the apps build as independent images with
# apps/<app> as the docker context, so a shared module has no home to live
# in, and keeping the copies byte-identical makes drift a one-line `cmp`
# instead of a merge.
module Sponsorship
  ENV_KEY = "SPONSORSHIP_URL"

  class InvalidDestination < Exception
    def initialize(raw : String)
      super("#{ENV_KEY} is not an absolute http(s) URL: #{raw.inspect}")
    end
  end

  # nil means sponsorship is not open. Callers never have to ask why.
  #
  # Writable so a spec can render the page in both states without reaching
  # into the process environment. The value that matters, the one production
  # boots with, still comes from resolve_destination below, and an invalid
  # one raises during boot, before the first request is served.
  class_property destination : URI? = resolve_destination

  def self.open? : Bool
    !@@destination.nil?
  end

  # Validates one configured value. Public so the boot path and the specs
  # exercise the same code: a set-but-malformed value is rejected here,
  # naming the variable, rather than discovered as a broken link.
  def self.parse(raw : String) : URI
    uri = URI.parse(raw.strip)

    # `absolute?` only proves a scheme is present; https:///nowhere parses
    # with neither error nor host, so the host is checked separately.
    host = uri.host
    unless uri.absolute? && {"http", "https"}.includes?(uri.scheme) && host && !host.blank?
      raise InvalidDestination.new(raw)
    end

    uri
  rescue URI::Error
    raise InvalidDestination.new(raw)
  end

  private def self.resolve_destination : URI?
    raw = ENV[ENV_KEY]?
    return nil if raw.nil? || raw.blank?

    parse(raw)
  end
end
