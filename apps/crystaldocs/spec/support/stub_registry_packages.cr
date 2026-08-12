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

  # Registers a repository, and optionally its releases. Versions are given as
  # strings because precedence is the interesting part and publication dates
  # are not; each gets a distinct timestamp so ordering is still observable.
  def publish(
    slug : String,
    name : String,
    versions : Array(String) = [] of String,
    yanked : Array(String) = [] of String,
    description : String? = nil,
  ) : StubRegistryPackages
    @packages[slug] = Package.new(
      slug: slug,
      name: name,
      description: description,
      repository_url: "https://#{slug}"
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
