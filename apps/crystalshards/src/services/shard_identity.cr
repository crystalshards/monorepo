# A shard's identity is the repository it comes from, not its name.
#
# Two different projects may both be called "router", one on GitHub and one on
# GitLab, and both belong in the registry. So the registry keys a shard on
# host + owner + repo, and `canonical_slug` ("github.com/kemalcr/kemal") is
# that identity as one string: it is the unique key in the database, the path
# in our URLs, and the payload workers carry on the queue.
#
# `repository_url` is untouched by all of this. It stays exactly as the host
# gave it to us and remains the outbound link to the real repository. The slug
# is our identifier for a repository, never a substitute for its URL.
module ShardIdentity
  # Identity is built only from characters every forge allows in an owner or
  # repository name. That is a deliberate floor rather than a guess at each
  # host's rules: anything outside it is reported as unparseable instead of
  # being mangled into an identity that would not round-trip through a URL.
  # It also makes the parts safe to interpolate into the backfill's SQL, which
  # cannot bind parameters.
  SEGMENT_PATTERN = /\A[A-Za-z0-9._-]+\z/

  # A host has to look like a host. This accepts "github.com" and
  # "git.example.co.uk" and rejects a bare "localhost", a host carrying a port
  # and anything with a path separator in it.
  HOST_PATTERN = /\A[a-z0-9][a-z0-9.-]*\.[a-z]{2,}\z/

  # https://host/owner/repo, with an optional .git suffix and trailing slash.
  HTTP_URL_PATTERN = %r{\Ahttps?://([^/\s]+)/([^/\s]+)/([^/\s]+?)(?:\.git)?/?\z}

  # git@host:owner/repo.git, the scp-like spelling git itself accepts.
  SCP_URL_PATTERN = %r{\A[^@\s]+@([^:\s]+):([^/\s]+)/([^/\s]+?)(?:\.git)?/?\z}

  # Raised when parts cannot form an identity the registry can address. A
  # crawler rescues this and skips the repository: the alternative is a row
  # nobody can reach by URL.
  class InvalidIdentityError < Exception
  end

  # The identity carried around before it is written to a row.
  record Identity, host : String, owner : String, repo : String do
    def canonical_slug : String
      "#{host}/#{owner}/#{repo}"
    end

    def url_path : String
      "/shards/#{canonical_slug}"
    end
  end

  # Why a URL produced no identity. Recorded on the row so the reason is
  # visible where the shard is, rather than being rediscovered later by
  # somebody wondering why their shard never indexed.
  record Rejection, reason : String

  alias Analysis = Identity | Rejection

  # The repository shapes this registry can address, stated rather than
  # implied. Identity is host + owner + repo on ANY host, in either of the two
  # URL spellings git itself accepts:
  #
  #   https://host/owner/repo[.git]
  #   git@host:owner/repo[.git]
  #
  # Deeper namespace paths (GitLab subgroups, nested Gitea organisations) are
  # deliberately OUT OF SCOPE, and this is the boundary rather than an
  # accident. The reason is structural: our URLs put the identity in the path
  # with real separators, as /shards/github.com/kemalcr/kemal, and the API
  # hangs sub-resources off it (/versions, /:version, /:version/download).
  # An unbounded namespace makes those undecidable, because
  # /api/shards/gitlab.com/group/sub/repo/1.0.0 could equally be version 1.0.0
  # of "group/sub/repo" or the repository "group/sub/repo/1.0.0". Supporting
  # both would mean encoding the identity into one segment and giving up the
  # URL shape the registry is specified to have.
  #
  # A nested repository is therefore refused with NESTED_NAMESPACE, counted,
  # and reported: never stored half-identified and never silently dropped.
  SUPPORTED_SHAPES = [
    "https://host/owner/repo",
    "http://host/owner/repo",
    "git@host:owner/repo",
  ]

  NESTED_NAMESPACE = "the repository sits in a nested namespace (host/group/subgroup/repo), " \
                     "which the registry cannot address yet: identities are host/owner/repo"
  NOT_A_REPO_URL   = "the URL does not name a repository on a host, as in https://host/owner/repo"
  UNUSABLE_HOST    = "the host is not a public hostname"
  UNUSABLE_SEGMENT = "the owner or repository name uses characters the registry cannot put in a URL"

  # Works out a URL's identity, or why it has none.
  #
  # Callers that only need the identity use `parse_url`. Callers that have to
  # explain themselves (the backfill, SaveShard's validation) use this, so the
  # explanation is the same in both places.
  def self.analyze(url : String?) : Analysis
    return Rejection.new(NOT_A_REPO_URL) if url.nil?

    candidate = url.strip
    return Rejection.new(NOT_A_REPO_URL) if candidate.empty?

    # A query string or fragment is never part of a repository's identity.
    candidate = candidate.split('?').first.split('#').first

    match = HTTP_URL_PATTERN.match(candidate) || SCP_URL_PATTERN.match(candidate)

    unless match
      return Rejection.new(nested_namespace?(candidate) ? NESTED_NAMESPACE : NOT_A_REPO_URL)
    end

    host = match[1].downcase
    owner = match[2]
    repo = match[3]

    return Rejection.new(UNUSABLE_HOST) unless HOST_PATTERN.matches?(host)
    return Rejection.new(UNUSABLE_SEGMENT) unless SEGMENT_PATTERN.matches?(owner)
    return Rejection.new(UNUSABLE_SEGMENT) unless SEGMENT_PATTERN.matches?(repo)

    Identity.new(host: host, owner: owner, repo: repo)
  end

  # Builds an identity out of a repository URL, or returns nil when the URL
  # does not name one addressable repository. nil is a real answer and every
  # caller handles it; `analyze` says why.
  def self.parse_url(url : String?) : Identity?
    case result = analyze(url)
    in Identity  then result
    in Rejection then nil
    end
  end

  # A path with more segments than owner/repo, which is the case worth naming
  # separately because it is an ordinary repository we cannot address rather
  # than a malformed URL.
  private def self.nested_namespace?(candidate : String) : Bool
    path = if match = %r{\Ahttps?://[^/\s]+/(.+)\z}.match(candidate)
             match[1]
           elsif match = %r{\A[^@\s]+@[^:\s]+:(.+)\z}.match(candidate)
             match[1]
           else
             return false
           end

    segments = path.chomp('/').sub(/\.git\z/, "").split('/').reject(&.empty?)
    segments.size > 2 && segments.all? { |segment| SEGMENT_PATTERN.matches?(segment) }
  end

  # Builds an identity from parts a crawler already has, applying the same
  # rules as `parse_url` so a crawler cannot introduce identities the URLs
  # cannot express.
  def self.build(host : String, owner : String, repo : String) : Identity?
    normalized_host = host.strip.downcase
    normalized_owner = owner.strip
    normalized_repo = repo.strip.sub(/\.git\z/, "")

    return nil unless HOST_PATTERN.matches?(normalized_host)
    return nil unless SEGMENT_PATTERN.matches?(normalized_owner)
    return nil unless SEGMENT_PATTERN.matches?(normalized_repo)

    Identity.new(host: normalized_host, owner: normalized_owner, repo: normalized_repo)
  end

  def self.slug_for(host : String, owner : String, repo : String) : String?
    build(host, owner, repo).try(&.canonical_slug)
  end

  # Resolves the key a route segment, a queue payload or an API path carries.
  #
  # A canonical slug is matched exactly. A bare name is honoured only when
  # exactly one shard answers to it, because the whole point of identity is
  # that "router" may name two shards: returning either one would be a guess
  # that silently indexes, documents or displays the wrong repository.
  def self.resolve(key : String?) : Shard?
    return nil if key.nil? || key.empty?

    ShardQuery.new.resolve(key)
  end

  # Records a repository the crawler found, keyed on its identity.
  #
  # Called for every repository on every sweep, so it updates the existing row
  # rather than creating a second one, and it never overwrites a stored value
  # with nothing: a crawler that cannot see a description this time around
  # leaves the description we already have alone. `stars` and `forks` follow the
  # same rule and need it more: only some enumerations measure them, so nil is
  # "this crawler did not look" and is never written over a count somebody else
  # did measure. Zero is written, because a repository nobody has starred is a
  # measurement and the ranking depends on telling it apart from unknown.
  #
  # Raises Avram::InvalidOperationError when the identity or URL is rejected.
  # A crawler should rescue that and skip the repository: failing loudly is the
  # point, since the alternative is a half-identified row.
  def self.upsert(
    host : String,
    owner : String,
    repo : String,
    repository_url : String,
    name : String,
    description : String? = nil,
    homepage_url : String? = nil,
    license : String? = nil,
    stars : Int32? = nil,
    forks : Int32? = nil,
  ) : Shard
    identity = build(host, owner, repo)

    unless identity
      raise InvalidIdentityError.new(
        "#{host}/#{owner}/#{repo} is not a repository identity the registry can address"
      )
    end

    existing = ShardQuery.new.canonical_slug(identity.canonical_slug).first?

    if existing
      operation = SaveShard.new(existing)
      operation.name.value = name
      operation.repository_url.value = repository_url
      operation.description.value = description if description
      operation.homepage_url.value = homepage_url if homepage_url
      operation.license.value = license if license
      operation.github_stars.value = stars unless stars.nil?
      operation.github_forks.value = forks unless forks.nil?
      # A repository we can see again is not missing any more.
      operation.unavailable_at.value = nil
      operation.update!
    else
      SaveShard.create!(
        name: name,
        description: description,
        repository_url: repository_url,
        homepage_url: homepage_url,
        license: license,
        github_stars: stars,
        github_forks: forks,
        host: identity.host,
        owner: identity.owner,
        repo: identity.repo,
        provider: provider_for(identity.host),
        repository_type: "git"
      )
    end
  end

  # Marks a repository the crawler can no longer see. The row stays: a shard
  # that vanished from a host is still what our download counts, dependency
  # edges and inbound links point at, and the repository may come back.
  # Returns nil when the identity is not in the registry, which is not an
  # error, just nothing to mark.
  def self.mark_unavailable(host : String, owner : String, repo : String, reason : String? = nil) : Shard?
    identity = build(host, owner, repo)
    return nil unless identity

    shard = ShardQuery.new.canonical_slug(identity.canonical_slug).first?
    return nil unless shard

    Log.info { "Marking #{identity.canonical_slug} unavailable: #{reason || "no reason given"}" }

    operation = SaveShard.new(shard)
    operation.unavailable_at.value = shard.unavailable_at || Time.utc
    operation.update!
  end

  # The provider column names the code path that talks to a host. It is
  # derived from the host so a crawler never has to pass it, and unknown hosts
  # get the generic git path rather than being refused.
  def self.provider_for(host : String) : String
    case host
    when "github.com"    then "github"
    when "gitlab.com"    then "gitlab"
    when "bitbucket.org" then "bitbucket"
    when "codeberg.org"  then "codeberg"
    else                      "git"
    end
  end

  # One pre-identity row, as the backfill reads it.
  record LegacyRow, id : Int64, name : String, repository_url : String

  # One row the backfill could not identify, and why.
  record UnidentifiedRow, row : LegacyRow, reason : String do
    def id : Int64
      row.id
    end

    def name : String
      row.name
    end

    def repository_url : String
      row.repository_url
    end
  end

  # What a backfill pass would do, worked out before anything is written.
  #
  # `statements` fills in the identity of every row whose URL names one
  # addressable repository, and records the reason on every row where it does
  # not. Nothing is dropped and nothing is guessed: an invented identity is a
  # shard nobody can reach, and a deleted row is somebody's dependency.
  record BackfillPlan, statements : Array(String), unparseable : Array(UnidentifiedRow) do
    def updated_count : Int32
      statements.size - unparseable.size
    end

    def total : Int32
      updated_count + unparseable.size
    end

    # Grouped for the migration's report, so an operator sees "4 nested
    # namespace paths" rather than four separate lines saying the same thing.
    def reasons : Hash(String, Array(UnidentifiedRow))
      unparseable.group_by(&.reason)
    end
  end

  def self.backfill_plan(rows : Array(LegacyRow)) : BackfillPlan
    statements = [] of String
    unparseable = [] of UnidentifiedRow

    rows.each do |row|
      case result = analyze(row.repository_url)
      in Identity
        statements << backfill_statement(row.id, result)
      in Rejection
        unparseable << UnidentifiedRow.new(row: row, reason: result.reason)
        statements << rejection_statement(row.id, result)
      end
    end

    BackfillPlan.new(statements: statements, unparseable: unparseable)
  end

  # A migration statement cannot bind parameters, so values are interpolated.
  # That is safe because the parts come from `analyze`, which accepts nothing
  # outside [A-Za-z0-9._-] and a hostname, and the reasons are this module's
  # own constants: no value can carry a quote or a statement separator.
  private def self.backfill_statement(id : Int64, identity : Identity) : String
    <<-SQL
    UPDATE shards SET
      host = '#{identity.host}',
      owner = '#{identity.owner}',
      repo = '#{identity.repo}',
      canonical_slug = '#{identity.canonical_slug}',
      identity_error = NULL
    WHERE id = #{id};
    SQL
  end

  # The row keeps its name, its URL, its downloads and its dependency edges.
  # What it gains is a stated reason it has no identity, where anyone looking
  # at the shard will see it.
  private def self.rejection_statement(id : Int64, rejection : Rejection) : String
    <<-SQL
    UPDATE shards SET identity_error = '#{rejection.reason}' WHERE id = #{id};
    SQL
  end
end
