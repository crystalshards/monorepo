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
    # `commit_sha` is the immutable revision the registry resolved the
    # version's tag to when it indexed the release, the same column
    # `DocsBuilder` on the crystalshards side checks a build out at. It is
    # nil for a release the registry indexed before that column existed, or
    # whose tag the provider could not resolve at index time.
    record Release, version : String, released_at : Time, yanked : Bool, commit_sha : String? = nil

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
      def key : String
        RegistryPackages.key(slug, name)
      end
    end

    # One offer from the typeahead: enough to draw a row and follow it, and
    # nothing else. The card fields are all absent on purpose, because reading
    # them would mean selecting and shipping five more columns per keystroke
    # for a list that shows a name.
    record Suggestion,
      slug : String?,
      name : String do
      def key : String
        RegistryPackages.key(slug, name)
      end
    end

    # What this app addresses a package by, decided once for every record here.
    #
    # `canonical_slug` is nullable for rows predating host qualified identity,
    # and `SaveShard` has required one since, so in practice this is always
    # the slug. When it is not, falling back to the name is the same choice
    # crystalshards makes in `Shard.url_path` and lands on the bare name route
    # this app still serves, which is where those rows live.
    #
    # It is also the key the local build state is joined on, because
    # `docs.package_name` holds exactly these two shapes.
    def self.key(slug : String?, name : String) : String
      slug || name
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

    # The typeahead's query, and deliberately not a narrower `CATALOGUE_SQL`.
    #
    # Three differences, each of them the reason this is separate. It counts
    # nothing, because a suggestion list has no pager to feed and the count is
    # the half of the catalogue statement that cannot be bounded by a LIMIT.
    # It reads two columns instead of six. And it matches prefixes rather than
    # anywhere in the row, which is what lets an index answer it: the browse
    # search is `%term%` and a btree cannot serve that, while `lower(name)
    # LIKE 'term%'` is served by the expression indexes crystalshards'
    # migration 17 adds to this table. The description is not matched at all,
    # for the same reason: a prefix of a description is not something anybody
    # types into a search box.
    #
    # Alphabetical, with the primary key breaking ties, and no documented-first
    # term. The catalogue leads with documented packages because a browser is
    # being shown where to start; a reader typing a name already knows which
    # package they want, and that ordering costs a scan of every built package
    # in the other database, which is not a per-keystroke price.
    SUGGEST_SQL = <<-SQL
      SELECT shards.canonical_slug, shards.name
      FROM shards
      WHERE lower(shards.name) LIKE $1
         OR lower(shards.canonical_slug) LIKE $1
      ORDER BY shards.name ASC, shards.id ASC
      LIMIT $2
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
      SELECT shard_versions.version, shard_versions.released_at, shard_versions.yanked,
             shard_versions.commit_sha
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

    # The packages whose name or repository starts with what the reader has
    # typed so far.
    #
    # An empty array when the registry cannot be reached, and that is the
    # right degradation here rather than the `unavailable` distinction
    # `catalogue` draws. A catalogue that came back empty would be a claim
    # that the ecosystem holds nothing, which the browse page has to refuse to
    # make; a suggestion list that comes back empty says only that there is
    # nothing to suggest, and the reader still has a search form that works.
    # Nothing caches it and nothing reads absence from it.
    def suggest(term : String, limit : Int32) : Array(Suggestion)
      return [] of Suggestion unless RegistryDatabase.configured?

      pattern = prefix_pattern(term)
      return [] of Suggestion unless pattern

      RegistryDatabase.query_all(
        SUGGEST_SQL,
        pattern,
        limit,
        as: {String?, String}
      ).map { |(slug, name)| Suggestion.new(slug: slug, name: name) }
    rescue ex
      Log.warn { "Could not read suggestions from the registry: #{ex.message}" }
      [] of Suggestion
    end

    # The bound parameter for a prefix match, or nil when there is nothing to
    # ask.
    #
    # Lowercased because the index holds `lower(...)`: a pattern carrying a
    # capital would match nothing rather than falling back to a scan, so this
    # is correctness and not only cost.
    #
    # `%` and `_` are LIKE's own wildcards and are escaped. A reader typing
    # "%" would otherwise match every shard in the registry, which is both the
    # wrong answer and the one input that turns a bounded index range into a
    # full scan. The backslash is escaped first, or it would escape the
    # escapes.
    private def prefix_pattern(term : String) : String?
      stripped = term.strip
      return nil if stripped.empty?

      escaped = stripped.downcase
        .gsub("\\", "\\\\")
        .gsub("%", "\\%")
        .gsub("_", "\\_")

      "#{escaped}%"
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
        as: {String, Time, Bool, String?}
      ).map { |(version, released_at, yanked, commit_sha)| Release.new(version, released_at, yanked, commit_sha) }
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

    # A dependency of one published version, resolved as far as this app can
    # act on it: the key it addresses the package by, and one release.
    #
    # Deliberately not a name and a requirement, which is what the registry
    # stores and what `RegistryMetadata::DeclaredDependency` carries. A
    # requirement cannot be built. A build needs one release, and it has to be
    # the release the parent's own requirement admits, because that is the one
    # a reader of the parent will meet.
    record ResolvedDependency, package_name : String, version : String

    # What one published version declares that other documentation depends on.
    #
    # `crystal_requirement` is `shard_versions.crystal_version`, which despite
    # the column name holds a requirement rather than a version: ">= 1.12.0"
    # and "1.2.0" are both real values in this system.
    #
    # `none` is the answer for a package the registry has never indexed, for a
    # version it does not hold, and for an environment with no registry
    # configured. All three mean the same thing to a caller: there is nothing
    # further to commission, and whatever was asked for directly is untouched.
    record Declaration,
      crystal_requirement : String?,
      dependencies : Array(ResolvedDependency) do
      def self.none : Declaration
        new(nil, [] of ResolvedDependency)
      end
    end

    # How a package key is matched against the registry.
    #
    # `Listing#key` addresses a row by its canonical slug and falls back to its
    # name only when the row has no slug, so a predicate matching slugs alone
    # would find nothing for every row that predates host qualified identity,
    # and one matching names alone would answer the wrong repository as soon as
    # two publish under one name. Both arms, with the slug winning.
    #
    # $1 is the key. It is interpolated into the statements below so the two
    # cannot drift apart, and it interpolates no caller data.
    PACKAGE_KEY_MATCH = <<-SQL
      (
        shards.canonical_slug = $1
        OR (shards.canonical_slug IS NULL AND shards.name = $1)
      )
      SQL

    # The version column is selected alongside the requirement purely so the
    # row has a column that is never NULL, exactly as `RegistryMetadata` does
    # it: reading only `crystal_version` makes "no such published version" and
    # "published, declared no Crystal" arrive as the same nil.
    CRYSTAL_REQUIREMENT_SQL = <<-SQL
      SELECT shard_versions.version, shard_versions.crystal_version
      FROM shard_versions
      JOIN shards ON shards.id = shard_versions.shard_id
      WHERE #{PACKAGE_KEY_MATCH}
        AND shard_versions.version = $2
      LIMIT 1
      SQL

    # Every runtime dependency of one published version, paired with every
    # release of that dependency the registry holds. One round trip, because
    # the alternative is a query per dependency on a path a reader is waiting
    # on.
    #
    # Development dependencies are excluded for the same reason
    # `RegistryMetadata` excludes them: a published API can only mention types
    # from what it links against at runtime, so a linter or a spec helper is
    # not documentation a reader of this package will follow a link into.
    #
    # The join onto `dependent_shards` is an inner join, and that is the
    # "registry does not know this dependency" rule rather than an oversight.
    # A dependency row carries a `dependent_shard_id` only when the registry
    # managed to resolve the shard.yml entry to a repository it has indexed,
    # and most runtime rows today have none. Without one there is no
    # repository to clone, no release list to resolve a requirement against
    # and no key to address a page by, so there is nothing to commission. Those
    # rows drop out here and the parent is unaffected.
    #
    # Yanked releases are excluded because the registry has already said not to
    # use them, so building one would spend a compile on documentation this
    # site would not choose to link to. A dependency whose every release is
    # yanked therefore contributes no rows at all, which reads the same way as
    # having none.
    DEPENDENCY_RELEASES_SQL = <<-SQL
      SELECT
        COALESCE(dependent_shards.canonical_slug, dependent_shards.name),
        dependencies.version_requirement,
        dependency_versions.version
      FROM dependencies
      JOIN shard_versions ON shard_versions.id = dependencies.shard_version_id
      JOIN shards ON shards.id = shard_versions.shard_id
      JOIN shards AS dependent_shards
        ON dependent_shards.id = dependencies.dependent_shard_id
      JOIN shard_versions AS dependency_versions
        ON dependency_versions.shard_id = dependent_shards.id
        AND dependency_versions.yanked = false
      WHERE #{PACKAGE_KEY_MATCH}
        AND shard_versions.version = $2
        AND dependencies.scope = 'runtime'
      SQL

    # What this exact release depends on, resolved to things this site can
    # address and build.
    #
    # Deliberately not rescued. The one caller commissions the package a reader
    # asked for before it asks this question, and rescues around the answer, so
    # a registry that breaks mid-request costs the cascade and nothing else.
    # Swallowing the failure here as well would put the reason in two places
    # and hide a broken registry from anything that ever calls this directly.
    def declaration(package_key : String, version : String) : Declaration
      return Declaration.none unless RegistryDatabase.configured?

      crystal_requirement = RegistryDatabase.query_all(
        CRYSTAL_REQUIREMENT_SQL,
        package_key,
        version,
        as: {String, String?}
      ).first?.try(&.[1])

      Declaration.new(crystal_requirement, resolved_dependencies(package_key, version))
    end

    private def resolved_dependencies(package_key : String, version : String) : Array(ResolvedDependency)
      requirements = {} of String => String
      releases = {} of String => Array(String)

      RegistryDatabase.query_all(
        DEPENDENCY_RELEASES_SQL,
        package_key,
        version,
        as: {String, String, String}
      ).each do |(key, requirement, release)|
        requirements[key] = requirement
        (releases[key] ||= [] of String) << release
      end

      resolved = [] of ResolvedDependency

      requirements.each do |key, raw|
        requirement = Semver::Requirement.parse?(raw)
        # A requirement this app cannot read is not a licence to pick a
        # release. It contributes nothing, exactly as the same string
        # contributes nothing when it reaches `DependencyIndex`.
        next unless requirement

        selected = self.class.best_version(releases[key], requirement)
        next unless selected

        resolved << ResolvedDependency.new(key, selected)
      end

      resolved
    end

    # The highest release satisfying a requirement, as the string the registry
    # holds rather than as a reparsed version.
    #
    # The string is what matters. It is the tag a build clones and the segment
    # a reader's URL carries, and rendering a parsed version back out loses the
    # difference between "1.2" and "1.2.0", which are not the same tag.
    #
    # Highest rather than lowest because that is what `shards` resolves a
    # requirement to, so it is the release the parent was actually built
    # against. Prereleases are excluded by `satisfied_by?` unless the
    # requirement names one, so this cannot pick an unshipped API by accident.
    #
    # Nil is a real answer: no release satisfies, or none of them parses. It
    # never means "take the newest instead".
    def self.best_version(versions : Array(String), requirement : Semver::Requirement) : String?
      best : Semver::Version? = nil
      chosen : String? = nil

      versions.each do |raw|
        parsed = Semver::Version.parse?(raw)
        next unless parsed
        next unless requirement.satisfied_by?(parsed)

        current = best
        if current.nil? || parsed > current
          best = parsed
          chosen = raw
        end
      end

      chosen
    end
  end
end
