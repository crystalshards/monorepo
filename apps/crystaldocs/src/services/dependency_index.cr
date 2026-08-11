module CrystalDocs
  # Maps type names owned by other indexed packages to pages we can render, so
  # a signature mentioning a type from another shard becomes a link into that
  # shard's documentation on this site rather than dead text.
  #
  # Scope is every package with a documented current version. Crystal's
  # docs.json does not record which shard a referenced type came from, and
  # this app persists no dependency graph, so there is nothing available to
  # narrow the lookup with.
  #
  # That makes ambiguity the real hazard: names like `Config` or `Error` get
  # defined by more than one shard, and picking a winner would send readers to
  # documentation for a different type entirely. So a name is linked only when
  # exactly one indexed package defines it. Anything owned by two or more stays
  # plain text, following the same rule as the type linker: a link that guesses
  # is worse than no link.
  class DependencyIndex
    CACHE_TTL = 10.minutes

    alias Location = NamedTuple(package: String, version: String)

    record Entry, index : Hash(String, Location), built_at : Time

    @@cache : Entry? = nil
    @@mutex = Mutex.new

    def self.for(doc_version : DocVersion) : Hash(String, Location)
      owner = doc_version.doc.package_name

      # A package never cross links to itself: those names resolve locally,
      # with current-page highlighting the external path lacks.
      build.reject { |_, location| location[:package] == owner }
    rescue ex
      Log.warn { "Could not build the cross-package type index: #{ex.message}" }
      {} of String => Location
    end

    def self.clear_cache
      @@mutex.synchronize { @@cache = nil }
    end

    private def self.build : Hash(String, Location)
      @@mutex.synchronize do
        if cached = @@cache
          next cached.index if Time.utc - cached.built_at <= CACHE_TTL
        end

        owners = {} of String => Array(Location)
        loader = DocsLoader.build

        documented_versions.each do |doc, version|
          document = loader.load(doc.package_name, version).document
          next unless document

          document.all_types.each do |type|
            list = owners[type.full_name] ||= [] of Location
            list << {package: doc.package_name, version: version}
          end
        end

        index = {} of String => Location
        owners.each do |full_name, locations|
          index[full_name] = locations.first if locations.size == 1
        end

        @@cache = Entry.new(index, Time.utc)
        index
      end
    end

    # Only current versions with a successful build, because those are the
    # ones we can actually render a page for.
    private def self.documented_versions : Array(Tuple(Doc, String))
      DocQuery.new.preload_doc_versions.results.compact_map do |doc|
        current = doc.current_version
        next unless current

        version = doc.doc_versions.find do |candidate|
          candidate.version == current && candidate.build_status == "success"
        end

        {doc, version.version} if version
      end
    end
  end
end
