module CrystalDocs
  # What the registry knows about a package, for the routes that have to answer
  # before this app has a row of its own.
  #
  # Documentation is built the first time somebody asks for a version, but
  # until now "asks for a version" meant a version this app already had a row
  # for, and rows only ever appeared after a build. A shard the registry has
  # indexed and nobody has documented yet had no reachable URL at all: the
  # version route looked for a Doc, found none, and raised route-not-found
  # before the lazy build could fire. Every one of the registry's shards was in
  # that state.
  #
  # So identity comes from the registry, the same connection `RegistryMetadata`
  # already uses and with the same reasoning: hand written SQL over a small,
  # stable set of columns rather than Avram models mirrored from crystalshards,
  # because a model would drag in schema enforcement and break this app's boot
  # whenever the registry gained a column.
  #
  # The key is `canonical_slug`, never `name`. A name is what a shard calls
  # itself and two repositories can pick the same one, so a name is a question
  # with more than one answer and a slug is the answer.
  class RegistryPackages
    # A shard, as the registry has it.
    #
    # `indexed_at` is here because an empty release list has two meanings and
    # only one of them is a fact about the repository. The registry records a
    # shard's identity when it discovers it and fetches its tags later, so a
    # freshly discovered shard has no version rows yet. Reading that as "this
    # repository publishes no releases" told visitors that kemal, which has 65
    # tags, had never cut one.
    #
    # nil means the registry has not looked. A time means it looked, and an
    # empty release list alongside one is then a real answer about the
    # repository.
    record Package,
      slug : String,
      name : String,
      description : String?,
      repository_url : String?,
      indexed_at : Time? do
      def indexed? : Bool
        !indexed_at.nil?
      end
    end

    # One published version. Yanked is carried rather than filtered, because a
    # yanked release is still a real release somebody may hold a link to; it is
    # only barred from being chosen as the default.
    record Release, version : String, released_at : Time, yanked : Bool

    # One row of the browse catalogue.
    #
    # Deliberately not `Package`, which the single-slug lookup returns. A
    # lookup answers "does this repository exist and where does it come from";
    # a listing answers "what should this row of the page say", which needs
    # the registry's own latest version and does not need the identity fields
    # that only matter once a reader has picked one package.
    record Listing,
      slug : String?,
      name : String,
      description : String?,
      repository_url : String?,
      latest_version : String? do
      # What this app addresses the package by.
      #
      # `canonical_slug` is nullable for rows predating host qualified
      # identity, and `SaveShard` has required one since, so in practice this
      # is always the slug. When it is not, falling back to the name is the
      # same choice crystalshards makes in `Shard#url_path` and lands on the
      # bare name route this app still serves, which is where those rows live.
      #
      # It is also the key the local build state is joined on, because
      # `docs.package_name` holds exactly these two shapes.
      def key : String
        slug || name
      end
    end

    # The outcome of asking the registry about one slug.
    #
    # "The registry says there is no such repository" and "the registry never
    # gave us an answer" are different facts, and collapsing both into a bare
    # nil is how a registry outage turns every documented package on the site
    # into a 404. Callers keep the distinction: absent is the answer that makes
    # a URL not exist, and unavailable falls back to whatever this app already
    # holds. The shape mirrors `DocsStorageService::Fetch`, which draws the
    # same line for the same reason.
    struct Lookup
      getter package : Package?

      def self.found(package : Package) : Lookup
        new(package, registry_answered: true)
      end

      # The registry answered, and it has no such repository.
      def self.absent : Lookup
        new(nil, registry_answered: true)
      end

      # No registry is configured, or the query failed, so whether the
      # repository exists is unknown.
      def self.unavailable : Lookup
        new(nil, registry_answered: false)
      end

      def initialize(@package : Package?, @registry_answered : Bool)
      end

      # True when "no package" is the registry's own answer rather than our
      # inability to ask.
      def registry_answered? : Bool
        @registry_answered
      end
    end

    # A page of the catalogue, and the total it was drawn from.
    #
    # The two travel together because they have to come from the same source.
    # A registry total over a page of local rows, or the reverse, paginates to
    # somewhere there is nothing.
    #
    # `unavailable` draws the same line `Lookup` does and for the same reason:
    # an empty catalogue is a claim that the ecosystem is empty, and a
    # registry we could not reach has not earned the right to make it. The
    # caller falls back to its own rows instead.
    struct Catalogue
      getter listings : Array(Listing)
      getter total : Int64

      def self.answered(listings : Array(Listing), total : Int64) : Catalogue
        new(listings, total, registry_answered: true)
      end

      def self.unavailable : Catalogue
        new([] of Listing, 0_i64, registry_answered: false)
      end

      def initialize(@listings : Array(Listing), @total : Int64, @registry_answered : Bool)
      end

      def registry_answered? : Bool
        @registry_answered
      end
    end

    # Test seam, mirroring the pattern the rest of the services use.
    class_property provider : Proc(RegistryPackages)? = nil

    def self.build : RegistryPackages
      if custom = @@provider
        custom.call
      else
        new
      end
    end

    PACKAGE_SQL = <<-SQL
      SELECT shards.canonical_slug, shards.name, shards.description,
             shards.repository_url, shards.indexed_at
      FROM shards
      WHERE shards.canonical_slug = $1
      LIMIT 1
      SQL

    # Ordered so that a collision is presented the same way twice running.
    SLUGS_SQL = <<-SQL
      SELECT shards.canonical_slug
      FROM shards
      WHERE shards.name = $1
        AND shards.canonical_slug IS NOT NULL
      ORDER BY shards.canonical_slug
      SQL

    # No predicate beyond the search arm, deliberately.
    #
    # crystalshards counts its listing with a bare `count(*)` over this table,
    # and the point of this whole path is that the two sites report the same
    # number. Any filter here, however defensible on its own, makes that
    # agreement a property of today's data rather than of the query, and a row
    # this app skipped would be invisible in exactly the way that started this.
    # A row with no canonical slug is still listable: it lists under its name.
    #
    # The search arm matches slug, name and description. Slug is included
    # because it is what the reader sees on the card and types back in, and a
    # search for "kemalcr" that misses github.com/kemalcr/kemal is a search
    # that does not resolve the thing on screen.
    CATALOGUE_WHERE = <<-SQL
      (
        $1::text IS NULL
        OR shards.name ILIKE $1
        OR shards.canonical_slug ILIKE $1
        OR shards.description ILIKE $1
      )
      SQL

    # The page and the total it was drawn from, in one statement.
    #
    # One query per page of results, so the cost of browsing does not scale
    # with what is on the page, and the count and the rows are read from one
    # snapshot rather than from two that a concurrent index run can separate.
    #
    # The LEFT JOIN is what makes it one statement rather than two. Folding
    # the count in with `count(*) OVER ()` returns nothing at all when the
    # page is empty, and an empty page is exactly where the pager still needs
    # the total, to tell a reader who asked for page 500 of 25 where they
    # actually are. Joining the page onto a single count row instead always
    # yields at least that row, so an empty page arrives as one row whose
    # package columns are null. Those columns are non-null in the table and
    # nullable here for that reason alone; the reader drops the sentinel by
    # testing `name`.
    #
    # Ordering is alphabetical with the primary key as the tiebreaker, and the
    # tiebreaker is not decoration. OFFSET pagination over a sort with ties
    # lets Postgres hand back the same row on two pages and skip another
    # entirely, because nothing obliges it to break a tie the same way twice,
    # and shard names tie whenever two repositories publish under one name.
    # `id` rather than `canonical_slug` because a nullable column cannot make
    # an order total.
    #
    # Recency is the obvious alternative and is the wrong key. The columns
    # that express it, pushed_at and latest_version, are only written once the
    # registry has indexed a shard, which is a minority of the rows; ordering
    # by one would sort those and shuffle the rest arbitrarily.
    # Documented packages lead, then name, then id.
    #
    # The leading term is the whole reason a visitor sees documentation on the
    # first page. Sorted by name alone the front of this catalogue was a run
    # of packages with nothing built, so the site read as empty while holding
    # plenty. `$4` carries the keys this app has actually built, read from the
    # other database, because build state and the catalogue do not live
    # together and no single statement can join them.
    #
    # An empty array is the neutral case rather than a special one: every row
    # scores the same and the order falls back to name.
    CATALOGUE_SQL = <<-SQL
      WITH filtered AS (
        SELECT shards.id, shards.canonical_slug, shards.name,
               shards.description, shards.repository_url,
               shards.latest_version,
               (COALESCE(shards.canonical_slug, shards.name) = ANY($4)) AS documented
        FROM shards
        WHERE #{CATALOGUE_WHERE}
      ),
      counted AS (
        SELECT count(*) AS total FROM filtered
      ),
      page AS (
        SELECT * FROM filtered
        ORDER BY filtered.documented DESC, filtered.name ASC, filtered.id ASC
        LIMIT $2 OFFSET $3
      )
      SELECT counted.total, page.canonical_slug, page.name,
             page.description, page.repository_url, page.latest_version
      FROM counted
      LEFT JOIN page ON true
      ORDER BY page.documented DESC, page.name ASC, page.id ASC
      SQL

    # How many shards the registry holds.
    #
    # `count(*)` with no predicate, which is exactly the query crystalshards
    # runs for the same stat. Anything narrower would reintroduce the
    # disagreement in a second place.
    TOTAL_PACKAGES_SQL = "SELECT count(*) FROM shards"

    # released_at is the tie break and never the sort key that matters: it is a
    # publication timestamp, and versions are ordered by precedence, which is
    # semver's job and is done in `default_release`. Ordering here only exists
    # so that two calls return the same array.
    RELEASES_SQL = <<-SQL
      SELECT shard_versions.version, shard_versions.released_at, shard_versions.yanked
      FROM shard_versions
      JOIN shards ON shards.id = shard_versions.shard_id
      WHERE shards.canonical_slug = $1
      ORDER BY shard_versions.released_at ASC, shard_versions.version ASC
      SQL

    # What the registry says about this slug.
    #
    # An unconfigured registry is unavailable rather than empty. An
    # environment without one cannot tell a real shard from an invented one,
    # and treating that as "no such shard" would 404 packages this app has
    # documentation for, while treating it as "shard exists" would commission
    # builds for anything anyone typed.
    #
    # A query that fails is the same kind of unknown, so it is reported rather
    # than raised. Documentation this app already holds is entirely ours to
    # serve, and taking it down because a second database is unreachable is a
    # worse failure than the one it would prevent.
    def find(slug : String) : Lookup
      return Lookup.unavailable unless RegistryDatabase.configured?

      rows = RegistryDatabase.query_all(
        PACKAGE_SQL,
        slug,
        as: {String, String, String?, String?, Time?}
      )

      row = rows.first?
      return Lookup.absent unless row

      Lookup.found(
        Package.new(
          slug: row[0],
          name: row[1],
          description: row[2],
          repository_url: row[3],
          indexed_at: row[4],
        )
      )
    rescue ex
      Log.warn { "Could not read #{slug} from the registry: #{ex.message}" }
      Lookup.unavailable
    end

    # Every repository publishing a shard under this name. Empty, one, or
    # several are all real answers and the callers treat them differently: a
    # bare name with one owner is a redirect, and with several there is no
    # correct single answer to redirect to.
    #
    # Empty is also what a registry we cannot reach produces, and that is the
    # right degradation here rather than a wrong one. The bare-name callers
    # read empty as "the registry has no claim on this name", which sends them
    # to their own rows, which is where the standard library and every legacy
    # artifact live. The failure mode is a name that should have redirected
    # serving locally instead, for as long as the registry is down.
    def slugs_for(name : String) : Array(String)
      return [] of String unless RegistryDatabase.configured?

      RegistryDatabase.query_all(SLUGS_SQL, name, as: String)
    rescue ex
      Log.warn { "Could not resolve the name #{name} against the registry: #{ex.message}" }
      [] of String
    end

    # A page of the catalogue, and the total it was drawn from.
    #
    # This is the set of shards that exist, which is the registry's answer and
    # never this app's. The local tables record which of them have had
    # documentation built, which is a different question and is joined on by
    # the caller.
    #
    # Two statements per page, and two is the whole budget: the count and the
    # page, neither of them proportional to the number of rows rendered. It is
    # not one because the alternatives that fold the count into the page lose
    # it precisely when the page comes back empty, which is the deep offset
    # case where the pager still has to tell the reader where they are.
    #
    # Unavailable rather than empty when the registry cannot answer, for the
    # reason `Lookup` draws the same line: an empty catalogue asserts that no
    # shard exists, and a database we could not reach has not established
    # that. Falling back to this app's own rows is specifically not the
    # degradation here. Those rows are build state, they are a fraction of the
    # ecosystem, and presenting them as the catalogue is the divergence this
    # path exists to remove.
    def catalogue(term : String?, limit : Int32, offset : Int32, documented : Array(String) = [] of String) : Catalogue
      return Catalogue.unavailable unless RegistryDatabase.configured?

      rows = RegistryDatabase.query_all(
        CATALOGUE_SQL,
        search_pattern(term),
        limit,
        offset,
        documented,
        as: {Int64, String?, String?, String?, String?, String?}
      )

      # No rows at all is impossible: the count side of the join always
      # produces one. Treating it as an empty catalogue rather than raising
      # keeps a shape change in the statement from taking the page down.
      total = rows.first?.try(&.[0]) || 0_i64

      listings = rows.compact_map do |(_, slug, name, description, repository_url, latest_version)|
        # The sentinel row an empty page arrives as. `name` is not nullable in
        # the table, so a null one is the join and never a shard.
        next unless name

        Listing.new(
          slug: slug,
          name: name,
          description: description,
          repository_url: repository_url,
          latest_version: latest_version,
        )
      end

      Catalogue.answered(listings, total)
    rescue ex
      Log.warn { "Could not read the catalogue from the registry: #{ex.message}" }
      Catalogue.unavailable
    end

    # An empty query is not a query. The form submits `query=` on every search
    # with the box cleared, and treating that as a pattern would match on
    # `%%`, which is every row and reads as though the filter did nothing.
    private def search_pattern(term : String?) : String?
      return nil unless term

      stripped = term.strip
      return nil if stripped.empty?

      "%#{stripped}%"
    end

    # How many shards the registry holds, or nil when it could not be asked.
    #
    # Nil rather than zero, and the caller shows no number rather than a
    # wrong one. "0 packages" on the landing page of a documentation site is a
    # worse answer than no stat at all.
    def total_packages : Int64?
      return nil unless RegistryDatabase.configured?

      RegistryDatabase.query_one(TOTAL_PACKAGES_SQL, as: Int64)
    rescue ex
      Log.warn { "Could not count the registry's shards: #{ex.message}" }
      nil
    end

    # Deliberately not rescued, unlike the two above.
    #
    # This is only ever called once `find` has said the repository exists, so
    # a failure here is a registry that broke mid-request rather than one that
    # was never reachable. Empty would then mean "this shard has no releases",
    # which for a shard with sixty-five of them is a lie the reader cannot see
    # through, and it would make the version route 404 releases that exist.
    # An error is the honest answer.
    def releases(slug : String) : Array(Release)
      return [] of Release unless RegistryDatabase.configured?

      RegistryDatabase.query_all(
        RELEASES_SQL,
        slug,
        as: {String, Time, Bool}
      ).map { |(version, released_at, yanked)| Release.new(version, released_at, yanked) }
    end

    # The version a reader gets when they ask for a package without naming one.
    #
    # Precedence, not recency. String order puts 1.10.0 below 1.9.0 and a
    # publication timestamp only records when a tag was seen, so neither
    # answers "which release is the current one".
    #
    # A yanked release is never the default, not even when it is the only
    # thing on offer. The registry has already said not to use it, and sending
    # a reader there by default contradicts that; a reader who names one in a
    # URL still gets it, because a withdrawn release is still a real release
    # somebody may hold a link to.
    #
    # A prerelease is only the default when nothing stable was ever tagged.
    # Semver ranks 2.0.0-rc1 above 1.9.0, so picking the highest version alone
    # sent every reader of a shard mid-release-candidate to documentation for
    # an API that has not shipped. This app already refuses that trade when it
    # resolves a dependency requirement, for the same reason.
    #
    # It is also what the registry itself decided: `shards.latest_version` is
    # written by crystalshards' `VersionOrder.latest_version`, which takes the
    # highest stable and falls back to a prerelease only when there is no
    # other. The browse card shows that column and its link resolves through
    # here, so a different rule here makes the badge disagree with the page it
    # links to.
    #
    # Nil means there is nothing to default to. That is a real answer twice
    # over: for the many indexed shards that have never cut a tag, and for a
    # shard whose every release has been withdrawn. The caller tells those two
    # apart from the release list itself.
    #
    # Three tiers, in the order crystalshards uses: the highest stable
    # release, else the highest prerelease, else a tag that is not semver at
    # all. An unparseable tag ranks below a prerelease rather than beside a
    # stable one, because "nightly" is not evidence of anything and must not
    # win over a real 2.0.0-rc1 just by being unrankable.
    def self.default_release(releases : Array(Release)) : Release?
      live = releases.reject(&.yanked)

      ranked = live.compact_map do |release|
        version = Semver::Version.parse?(release.version)
        version ? {release, version} : nil
      end

      stable = ranked.reject { |(_, version)| version.prerelease? }
      candidates = stable.empty? ? ranked : stable

      # The fallback is a release whose version string is not semver at all.
      # The SQL orders the list, so it is at least the same answer every time
      # rather than whichever row came back first.
      highest(candidates) || live.last?
    end

    private def self.highest(candidates : Array(Tuple(Release, Semver::Version))) : Release?
      best : Semver::Version? = nil
      chosen : Release? = nil

      candidates.each do |(release, version)|
        current = best
        if current.nil? || version > current
          best = version
          chosen = release
        end
      end

      chosen
    end
  end
end
