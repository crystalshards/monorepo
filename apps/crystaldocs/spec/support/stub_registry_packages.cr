# A registry with a scripted answer.
#
# The real reader is hand written SQL against a database another app owns, so
# examples about what a URL means script the answers here rather than planting
# rows in crystalshards' schema. That also keeps this suite from depending on
# another app's migrations having been run, and from reading a database a
# concurrent crystalshards run is truncating between examples.
class StubRegistryPackages < CrystalDocs::RegistryPackages
  alias Package = CrystalDocs::RegistryPackages::Package
  alias Release = CrystalDocs::RegistryPackages::Release
  alias Lookup = CrystalDocs::RegistryPackages::Lookup
  alias Listing = CrystalDocs::RegistryPackages::Listing
  alias Catalogue = CrystalDocs::RegistryPackages::Catalogue
  alias Suggestion = CrystalDocs::RegistryPackages::Suggestion

  getter packages : Hash(String, Package)
  getter releases : Hash(String, Array(Release))

  # Whether the registry answers at all. False is the "no registry configured,
  # or it could not be reached" case, which is a different answer from "no such
  # package" and the routes treat it differently.
  property? reachable : Bool

  def initialize(
    @packages : Hash(String, Package) = {} of String => Package,
    @releases : Hash(String, Array(Release)) = {} of String => Array(Release),
    @reachable : Bool = true,
  )
  end

  def find(slug : String) : Lookup
    return Lookup.unavailable unless reachable?

    if package = @packages[slug]?
      Lookup.found(package)
    else
      Lookup.absent
    end
  end

  def slugs_for(name : String) : Array(String)
    return [] of String unless reachable?

    @packages.values.select { |package| package.name == name }.map(&.slug).sort!
  end

  def releases(slug : String) : Array(Release)
    return [] of Release unless reachable?

    @releases[slug]? || [] of Release
  end

  # The browse catalogue, answered from the same scripted packages.
  #
  # Overridden rather than inherited, and that is load bearing. The real
  # reader would consult `RegistryDatabase`, which in this suite is either
  # unconfigured, making every browse example assert against the outage page,
  # or configured, making them read a database another app owns and truncates.
  # Neither tests this app's listing.
  #
  # Ordering, the search arm and the offset window are reproduced here because
  # they are what the examples are about. They mirror `CATALOGUE_SQL`:
  # documented packages first, then name ascending with a stable tiebreaker,
  # matching on slug, name or description.
  #
  # The documented arm has to be mirrored too. Without it this stub would
  # order by name alone, and the examples that assert a documented package
  # leads the page would pass against a stub that cannot express the thing
  # they are testing.
  def catalogue(term : String?, limit : Int32, offset : Int32, documented : Array(String) = [] of String) : Catalogue
    return Catalogue.unavailable unless reachable?

    matched = @packages.values.select { |package| matches?(package, term) }
      .sort_by { |package| {documented.includes?(package.slug) ? 0 : 1, package.name, package.slug} }

    listings = matched[offset, limit]? || [] of Package

    Catalogue.answered(
      listings.map do |package|
        Listing.new(
          slug: package.slug,
          name: package.name,
          description: package.description,
          repository_url: package.repository_url,
          latest_version: latest_version_for(package.slug),
        )
      end,
      matched.size.to_i64
    )
  end

  # Overridden for the same reason as `catalogue`: inherited, it would consult
  # `RegistryDatabase` and answer nil in this suite, so the landing page would
  # print no package count in every example and nothing would be asserting on
  # the number this change exists to correct.
  def total_packages : Int64?
    return nil unless reachable?

    @packages.size.to_i64
  end

  # The typeahead, answered from the same scripted packages and overridden for
  # the same reason `catalogue` is: inherited, it would query `RegistryDatabase`
  # and answer from a database another app owns and truncates.
  #
  # Prefix matching, name or slug, alphabetical, capped by the limit. Those are
  # the four things `SUGGEST_SQL` does and the four things the examples are
  # about, so the stub has to do all of them or an example asserting a prefix
  # would pass against a stub that matches anywhere.
  def suggest(term : String, limit : Int32) : Array(Suggestion)
    return [] of Suggestion unless reachable?

    needle = term.strip.downcase
    return [] of Suggestion if needle.empty?

    @packages.values
      .select do |package|
        package.name.downcase.starts_with?(needle) ||
          package.slug.downcase.starts_with?(needle)
      end
      .sort_by { |package| {package.name, package.slug} }
      .first(limit)
      .map { |package| Suggestion.new(slug: package.slug, name: package.name) }
  end

  private def matches?(package : Package, term : String?) : Bool
    return true unless term

    stripped = term.strip
    return true if stripped.empty?

    needle = stripped.downcase

    package.name.downcase.includes?(needle) ||
      package.slug.downcase.includes?(needle) ||
      !!package.description.try(&.downcase.includes?(needle))
  end

  # Stands in for `shards.latest_version`, which the registry writes when it
  # indexes a shard.
  #
  # Resolved with `default_release` rather than by taking the last one
  # published, so the stub answers by precedence exactly as the repository
  # route does when it decides where the card's link lands. Taking insertion
  # order would let an example script releases out of order and assert a
  # badge the real site would never show.
  private def latest_version_for(slug : String) : String?
    releases = @releases[slug]? || [] of Release

    CrystalDocs::RegistryPackages.default_release(releases).try(&.version)
  end

  # Registers a repository, and optionally its releases. Versions are given as
  # strings because precedence is the interesting part and publication dates
  # are not; each gets a distinct timestamp so ordering is still observable.
  #
  # `indexed` defaults true because almost every spec here is about a
  # repository the registry has already read. Pass false for the state that
  # produced the bug: discovered, not yet read, so an empty release list is a
  # gap in our database rather than a fact about the repository.
  def publish(
    slug : String,
    name : String,
    versions : Array(String) = [] of String,
    yanked : Array(String) = [] of String,
    description : String? = nil,
    indexed : Bool = true,
  ) : StubRegistryPackages
    @packages[slug] = Package.new(
      slug: slug,
      name: name,
      description: description,
      repository_url: "https://#{slug}",
      indexed_at: indexed ? Time.utc(2024, 1, 1) : nil,
    )

    @releases[slug] = versions.map_with_index do |version, index|
      Release.new(version, Time.utc(2024, 1, 1) + index.days, yanked.includes?(version))
    end

    self
  end

  def install : StubRegistryPackages
    registry = self
    CrystalDocs::RegistryPackages.provider = -> { registry.as(CrystalDocs::RegistryPackages) }
    self
  end

  def self.install : StubRegistryPackages
    new.install
  end
end

# Every example gets a registry that knows nothing, whether or not it asked for
# one.
#
# Without this the real reader runs, which means every bare-name URL in the
# suite queries a database another app owns. That is a dependency on
# crystalshards' migrations having been applied to answer a question about this
# app's routes, and it makes the suite's result depend on whatever a concurrent
# run in that app is doing to its own test database.
Spec.before_each do
  StubRegistryPackages.install
end

Spec.after_each do
  CrystalDocs::RegistryPackages.provider = nil
end
