module CrystalDocs
  # Where a package's documentation lives on this site, decided in one place.
  #
  # A Doc row is addressed by the key it carries, and there are two kinds of
  # key.
  #
  #   * Host qualified ("github.com/kemalcr/kemal"), which is the identity the
  #     registry hands out. It is the only key that survives two repositories
  #     publishing a shard under the same name, and every row this app creates
  #     from the registry carries one.
  #   * Bare ("crystal"), which belongs to a package the registry does not
  #     know. Today that is the standard library and the handful of rows that
  #     predate host qualified identity. Those URLs are live and indexed, so
  #     they keep resolving to exactly what they resolve to now.
  #
  # The two shapes cannot share a route, and the reason is worth writing down.
  # `Docs::Type` ends in a glob, and LuckyRouter registers a glob's base path
  # as well, so `/docs/:package_name/:version/:top_level/*:rest` claims every
  # path from four segments deep onwards. A host qualified path spelled as bare
  # segments would be swallowed by it and read as package "github.com" at
  # version "kemalcr".
  #
  # A static segment settles it: LuckyRouter tries static parts before dynamic
  # ones and backtracks when the static subtree has no match, so "_" is matched
  # before `:package_name` is ever considered, and a path that only looks like
  # a canonical one still falls through to the legacy routes. It is spelled "_"
  # rather than a word because a word can be a shard name, and a shard actually
  # called "repo" would lose its own deep type URLs to the canonical route. It
  # is an underscore rather than a hyphen because Lucky enforces underscored
  # route segments.
  module PackagePaths
    # The segment that says "what follows is a repository, not a package name".
    CANONICAL_SEGMENT = "_"

    # True when this key names a repository rather than a bare package.
    #
    # The separator is the discriminator, exactly as it is in crystalshards,
    # where `Shard#url_path` picks between a slug path and a name path the same
    # way. A registry slug always has two separators and a shard name never has
    # any, so no key is ambiguous.
    def self.canonical?(package_name : String) : Bool
      package_name.includes?('/')
    end

    def self.package_path(package_name : String) : String
      if canonical?(package_name)
        "/docs/#{CANONICAL_SEGMENT}/#{package_name}"
      else
        "/docs/#{package_name}"
      end
    end

    def self.version_path(package_name : String, version : String) : String
      "#{package_path(package_name)}/#{version}"
    end

    def self.type_path(package_name : String, version : String, type_path : String) : String
      "#{version_path(package_name, version)}/#{type_path}"
    end

    # The absolute form, for the sibling sites that link here.
    def self.package_url(package_name : String, host : String) : String
      "#{host}#{package_path(package_name)}"
    end
  end
end
