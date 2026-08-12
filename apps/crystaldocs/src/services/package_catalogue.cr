module CrystalDocs
  # What this site lists, and what it knows about each thing it lists.
  #
  # Those are two different questions with two different answers, and running
  # them together is what made the sites disagree. The set of packages that
  # exist is the registry's answer: crystalshards indexes the ecosystem and is
  # the only writer for it. Whether a given package has documentation built is
  # ours, and lives in `docs` and `doc_versions`.
  #
  # Browsing used to ask the second question and present the answer as though
  # it were the first. A `docs` row is only ever created when somebody visits a
  # package's version URL, by `PackageRegistration`, so the browse list was the
  # set of packages a human or a crawler had happened to open. That is why the
  # totals diverged: crystalshards counted the ecosystem and crystaldocs
  # counted its own traffic.
  #
  # So the catalogue is the registry's, and the local rows are joined onto the
  # page as build state. Two statements per page and neither scales with the
  # number of rows on it: one to the registry for the page and its total, one
  # here for the build state of the keys that came back.
  class PackageCatalogue
    # One row of the catalogue: what the registry says about a package, and
    # what this app has built for it.
    #
    # Most of the fields that come from this app are nil for most packages,
    # because most packages have no local row at all. That is a displayable
    # state and not a missing one: the card links to a URL that registers the
    # package and commissions a build the first time it is visited.
    record Entry,
      key : String,
      name : String?,
      description : String?,
      repository_url : String?,
      version : String?,
      built_versions : Int32,
      last_updated_at : Time?,
      total_views : Int64,
      created_at : Time?,
      updated_at : Time? do
      # What the card leads with.
      #
      # The shard's own name, because that is what a reader is looking for and
      # what the catalogue is ordered by; leading with the slug ordered the
      # page by a string nobody could see. Nil for a row that came from this
      # app's tables rather than the registry, where the key is all there is.
      def heading : String
        name || key
      end

      # True when the repository is worth showing beside the name, which is
      # whenever the name is not already the whole identity. Two repositories
      # can publish the same shard name, so the name alone does not say which
      # package this is.
      def qualified? : Bool
        heading != key
      end

      # Whether documentation has actually been built for this package.
      #
      # Counted from `doc_versions.build_status`, the same signal
      # `DependencyIndex` uses to decide a cross-package link is safe to make.
      # Not from the presence of a `docs` row, which only says somebody asked,
      # and not from `last_updated_at`, which nothing in this app writes.
      def documented? : Bool
        built_versions > 0
      end

      def path : String
        PackagePaths.package_path(key)
      end
    end

    # A page of the catalogue.
    #
    # `available` is false when the registry could not be reached. The page
    # says so rather than showing this app's own rows in its place: those rows
    # are build state, they are a fraction of the ecosystem, and presenting
    # them as the catalogue is the exact divergence this class exists to
    # remove. A wrong total quietly replacing a right one is the failure that
    # started this, and it must not come back on a timer.
    record Page,
      entries : Array(Entry),
      total : Int64,
      available : Bool do
      def available? : Bool
        available
      end
    end

    # Everything the card needs about local build state, for a page of keys, in
    # one statement.
    #
    # Aggregated rather than preloaded. `preload_doc_versions` would answer the
    # same question by loading every version row of every package on the page,
    # which for a package with sixty-five tags is sixty-five rows to compute
    # one boolean.
    BUILD_STATE_SQL = <<-SQL
      SELECT docs.package_name,
             docs.current_version,
             docs.description,
             docs.repository_url,
             docs.total_views,
             docs.last_updated_at,
             docs.created_at,
             docs.updated_at,
             count(doc_versions.id) FILTER (
               WHERE doc_versions.build_status = 'success'
             ) AS built_versions
      FROM docs
      LEFT JOIN doc_versions ON doc_versions.doc_id = docs.id
      WHERE docs.package_name IN (%{placeholders})
      GROUP BY docs.id
      SQL

    record BuildState,
      current_version : String?,
      description : String?,
      repository_url : String?,
      total_views : Int64,
      last_updated_at : Time?,
      created_at : Time,
      updated_at : Time,
      built_versions : Int32

    def self.page(query : String?, page : Int32, per_page : Int32) : Page
      offset = (page - 1) * per_page
      catalogue = RegistryPackages.build.catalogue(query, per_page, offset)

      unless catalogue.registry_answered?
        return Page.new([] of Entry, 0_i64, available: false)
      end

      listings = catalogue.listings
      state = build_state(listings.map(&.key))

      entries = listings.map do |listing|
        held = state[listing.key]?

        Entry.new(
          key: listing.key,
          name: listing.name,
          # The registry's description is the fresher of the two: the local
          # copy was taken from it when the package was registered and is
          # never refreshed. Ours is the fallback for a row the registry has
          # no description for.
          description: listing.description || held.try(&.description),
          repository_url: listing.repository_url || held.try(&.repository_url),
          # The registry's version, not this app's, because the registry's is
          # where the card's link actually lands: the repository route asks
          # the registry for the current release and redirects there. Showing
          # `docs.current_version` instead put a badge on the card that
          # disagreed with the page one click away, and it is a stale copy of
          # this same fact besides, written once when the package was first
          # registered and never refreshed.
          version: listing.latest_version || held.try(&.current_version),
          built_versions: held.try(&.built_versions) || 0,
          last_updated_at: held.try(&.last_updated_at),
          total_views: held.try(&.total_views) || 0_i64,
          created_at: held.try(&.created_at),
          updated_at: held.try(&.updated_at),
        )
      end

      Page.new(entries, catalogue.total, available: true)
    end

    # The local build state for a set of package keys.
    def self.build_state(keys : Array(String)) : Hash(String, BuildState)
      state = {} of String => BuildState
      return state if keys.empty?

      # Placeholders are generated from the count, never from the keys, so the
      # keys stay bound parameters.
      placeholders = (1..keys.size).join(", ") { |position| "$#{position}" }
      sql = BUILD_STATE_SQL % {placeholders: placeholders}

      rows = AppDatabase.query_all(
        sql,
        args: keys.map(&.as(DB::Any)),
        as: {String, String?, String?, String?, Int64, Time?, Time, Time, Int64}
      )

      rows.each do |row|
        state[row[0]] = BuildState.new(
          current_version: row[1],
          description: row[2],
          repository_url: row[3],
          total_views: row[4],
          last_updated_at: row[5],
          created_at: row[6],
          updated_at: row[7],
          built_versions: row[8].to_i,
        )
      end

      state
    end

    # The same shape, for a list this app has already read out of its own
    # tables. The home page's "recently updated" and "popular" sections are
    # genuinely about documentation this site has built, so they keep reading
    # local rows; this only puts them in the shape the card renders.
    def self.for_docs(docs : Enumerable(Doc)) : Array(Entry)
      rows = docs.to_a
      state = build_state(rows.map(&.package_name))

      rows.map do |doc|
        held = state[doc.package_name]?

        Entry.new(
          key: doc.package_name,
          # No registry name here: a `docs` row carries only the key. The card
          # leads with the key, which is what these sections showed before.
          name: nil,
          description: doc.description,
          repository_url: doc.repository_url,
          version: doc.current_version,
          built_versions: held.try(&.built_versions) || 0,
          last_updated_at: doc.last_updated_at,
          total_views: doc.total_views,
          created_at: held.try(&.created_at),
          updated_at: held.try(&.updated_at),
        )
      end
    end
  end
end
