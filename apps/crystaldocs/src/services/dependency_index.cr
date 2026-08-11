module CrystalDocs
  # The Crystal standard library is published through the same pipeline as
  # every shard, so it is simply the package with this name. One identifier
  # for registration, indexing, collision resolution and URLs.
  CORE_PACKAGE = "crystal"

  # Maps type names that a package's documentation can mention to pages we can
  # render, so a signature naming a type from another shard becomes a link
  # into that shard's documentation on this site rather than dead text.
  #
  # The index is built for one specific version of one specific package,
  # because that is the only thing that makes a link correct. A reader on
  # kemal 1.2.0 has to reach the dependency versions kemal 1.2.0 asked for,
  # documented against the Crystal it declared support for. Resolving a name
  # to whichever package defines it at that package's newest version shows
  # readers API that did not exist when their release shipped, which is worse
  # than showing them nothing.
  #
  # Two registry facts drive the selection, and neither is ours:
  # `dependencies.version_requirement` for this exact shard version, and
  # `shard_versions.crystal_version`. `RegistryMetadata` explains how they are
  # read.
  #
  # Nothing here falls back to newest. A dependency with no satisfying
  # documented version, or with metadata we cannot read, contributes no names
  # at all, and those names stay plain text.
  #
  # Ambiguity is the other hazard: names like `Config` or `Error` are defined
  # by more than one shard, and picking a winner sends a reader to a different
  # type entirely. A name owned by two of the selected packages stays plain
  # text, unless one of them is the standard library, which is the canonical
  # home of a standard library name and would otherwise go dark everywhere,
  # since shards reopen `String` and `Array` routinely.
  class DependencyIndex
    CACHE_TTL = 10.minutes

    alias Location = NamedTuple(package: String, version: String)

    record Entry, index : Hash(String, Location), built_at : Time

    @@cache = {} of String => Entry
    @@mutex = Mutex.new

    # Takes the owning package and version by name rather than reading them
    # back off a DocVersion. That association is not always preloaded, and
    # Avram raises when it is not, which the rescue below would swallow into
    # an empty index and silently turn every cross link into plain text.
    def self.for(package_name : String, version : String) : Hash(String, Location)
      key = "#{package_name}/#{version}"

      if cached = read_cache(key)
        return cached
      end

      index = resolve(package_name, version)
      write_cache(key, index)
      index
    rescue ex
      # An unreachable registry is not a reason to fail a page that is
      # otherwise renderable, and every unresolved name already has a defined
      # rendering: plain text.
      Log.warn { "Could not build the dependency index for #{package_name} #{version}: #{ex.message}" }
      no_links
    end

    def self.clear_cache
      @@mutex.synchronize { @@cache.clear }
    end

    private def self.resolve(package_name : String, version : String) : Hash(String, Location)
      registry = RegistryMetadata.build

      source = registry.source(package_name, version)
      # Documented here but unknown to the registry, so there is no declared
      # dependency set to honour and nothing that can be resolved correctly.
      return no_links unless source

      crystal_requirement = Semver::Requirement.parse?(source.crystal_requirement)
      # The version never declared which Crystal it supports, so neither the
      # standard library nor any dependency can be pinned to the right era.
      return no_links unless crystal_requirement

      names = source.dependencies.map(&.name)
      names << CORE_PACKAGE
      names.uniq!
      documented = documented_versions(names)

      # The Crystal version this artifact is read against, chosen from the
      # standard library builds we hold. Taking it from our own documentation
      # rather than from the registry keeps it to versions that can actually
      # be linked, and the standard library reaches this site through the same
      # pipeline as every other package, so it is here.
      selected_crystal = highest(
        (documented[CORE_PACKAGE]? || Set(String).new).map do |core_version|
          RegistryMetadata::PublishedVersion.new(core_version, nil)
        end,
        crystal_requirement,
        nil
      )
      return no_links unless selected_crystal

      # Reparsed rather than threaded through, because the selection above
      # deals in the strings that address a page and this deals in ordering.
      crystal = Semver::Version.parse?(selected_crystal)
      return no_links unless crystal

      locations = [] of Location
      locations << {package: CORE_PACKAGE, version: selected_crystal}

      published = registry.published_versions(names)

      source.dependencies.each do |dependency|
        # Core is never resolved through a declared dependency: a shard does
        # not list the standard library, and the Crystal requirement above is
        # the authority on which version applies.
        next if dependency.name == CORE_PACKAGE

        requirement = Semver::Requirement.parse?(dependency.requirement)
        next unless requirement

        candidates = published[dependency.name]?
        next unless candidates

        available = documented[dependency.name]?
        next unless available

        selected = highest(
          candidates.select { |candidate| available.includes?(candidate.version) },
          requirement,
          crystal
        )
        next unless selected

        locations << {package: dependency.name, version: selected}
      end

      index_for(locations, package_name)
    end

    # The highest version that satisfies `requirement`, or nil when none does.
    # Nil is a real answer here and never means "use the newest instead".
    #
    # When `crystal` is given, a candidate also has to declare support for it.
    # That is the check that stops a page built against an older compiler from
    # linking into a dependency release that needs a newer one. A candidate
    # that declared no Crystal support at all cannot be shown to be safe, and
    # a guess is the bug this exists to remove, so it is skipped.
    private def self.highest(
      candidates : Enumerable(RegistryMetadata::PublishedVersion),
      requirement : Semver::Requirement,
      crystal : Semver::Version?,
    ) : String?
      best : Semver::Version? = nil
      best_version : String? = nil

      candidates.each do |candidate|
        parsed = Semver::Version.parse?(candidate.version)
        next unless parsed
        next unless requirement.satisfied_by?(parsed)

        if wanted = crystal
          support = Semver::Requirement.parse?(candidate.crystal_requirement)
          next unless support
          next unless support.satisfied_by?(wanted)
        end

        current = best
        if current.nil? || parsed > current
          best = parsed
          best_version = candidate.version
        end
      end

      best_version
    end

    # Only versions with a successful build, because those are the only ones
    # we can render a page for.
    private def self.documented_versions(package_names : Array(String)) : Hash(String, Set(String))
      documented = {} of String => Set(String)
      return documented if package_names.empty?

      DocQuery.new.preload_doc_versions.package_name.in(package_names).results.each do |doc|
        versions = Set(String).new

        doc.doc_versions.each do |doc_version|
          versions << doc_version.version if doc_version.build_status == "success"
        end

        documented[doc.package_name] = versions
      end

      documented
    end

    private def self.index_for(locations : Array(Location), package_name : String) : Hash(String, Location)
      owners = {} of String => Array(Location)
      loader = DocsLoader.build

      locations.each do |location|
        # A package never cross links to itself: those names resolve locally,
        # with current page highlighting the external path lacks.
        next if location[:package] == package_name

        document = loader.load(location[:package], location[:version]).document
        next unless document

        document.all_types.each do |type|
          list = owners[type.qualified_name] ||= [] of Location
          list << location
        end
      end

      index = no_links

      owners.each do |qualified_name, candidates|
        if candidates.size == 1
          index[qualified_name] = candidates.first
        elsif core = candidates.find { |candidate| candidate[:package] == CORE_PACKAGE }
          index[qualified_name] = core
        end
      end

      index
    end

    private def self.no_links : Hash(String, Location)
      {} of String => Location
    end

    private def self.read_cache(key : String) : Hash(String, Location)?
      @@mutex.synchronize do
        entry = @@cache[key]?
        next nil unless entry

        if Time.utc - entry.built_at > CACHE_TTL
          @@cache.delete(key)
          nil
        else
          entry.index
        end
      end
    end

    private def self.write_cache(key : String, index : Hash(String, Location))
      @@mutex.synchronize { @@cache[key] = Entry.new(index, Time.utc) }
    end
  end
end
