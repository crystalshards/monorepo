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
    record Package,
      slug : String,
      name : String,
      description : String?,
      repository_url : String?

    # One published version. Yanked is carried rather than filtered, because a
    # yanked release is still a real release somebody may hold a link to; it is
    # only barred from being chosen as the default.
    record Release, version : String, released_at : Time, yanked : Bool

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
      SELECT shards.canonical_slug, shards.name, shards.description, shards.repository_url
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
        as: {String, String, String?, String?}
      )

      row = rows.first?
      return Lookup.absent unless row

      Lookup.found(
        Package.new(slug: row[0], name: row[1], description: row[2], repository_url: row[3])
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
    # Nil means there is nothing to default to. That is a real answer twice
    # over: for the many indexed shards that have never cut a tag, and for a
    # shard whose every release has been withdrawn. The caller tells those two
    # apart from the release list itself.
    def self.default_release(releases : Array(Release)) : Release?
      live = releases.reject(&.yanked)

      # `last?` is the fallback for a release whose version string is not
      # semver at all. The SQL orders the list, so it is at least the same
      # answer every time rather than whichever row came back first.
      highest(live) || live.last?
    end

    private def self.highest(releases : Array(Release)) : Release?
      best : Semver::Version? = nil
      chosen : Release? = nil

      releases.each do |release|
        parsed = Semver::Version.parse?(release.version)
        next unless parsed

        current = best
        if current.nil? || parsed > current
          best = parsed
          chosen = release
        end
      end

      chosen
    end
  end
end
