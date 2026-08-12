require "../services/shard_identity"

class SaveShard < Shard::SaveOperation
  # canonical_slug is deliberately not permitted: it is computed from
  # host/owner/repo so a caller cannot hand us a slug that disagrees with the
  # identity it claims to describe.
  permit_columns :name, :description, :repository_url, :homepage_url,
    :documentation_url, :license, :total_downloads, :github_stars,
    :github_forks, :last_synced_at, :provider, :repository_type,
    :readme_content, :host, :owner, :repo, :unavailable_at,
    :topics, :default_branch, :pushed_at, :archived, :latest_version,
    :indexed_at, :index_attempted_at, :index_error

  before_save do
    derive_identity
    set_default_values
    validate_required name, repository_url, provider, repository_type
    validate_required host, owner, repo, canonical_slug,
      message: "is required: a shard is identified by the repository it comes from"
    validate_uniqueness_of canonical_slug,
      message: "is already registered: this repository is already in the registry"
    validate_url_format
  end

  private def set_default_values
    total_downloads.value ||= 0_i64
    provider.value ||= "github"
    repository_type.value ||= "git"
  end

  # Identity follows the repository.
  #
  # Explicit parts win when a caller actually supplied them in this save: a
  # crawler knows the host's own notion of owner and repo, including any
  # canonicalisation the host applied. Otherwise a changed repository_url is
  # authoritative, because pointing a row at a different repository changes
  # which repository it is; keeping the old identity would leave the row
  # claiming to be one repository while linking to another. A save that
  # touches neither recomputes the slug from the parts already on the row, so
  # the slug can never drift from them.
  private def derive_identity
    if host.changed? || owner.changed? || repo.changed?
      if (h = host.value) && (o = owner.value) && (r = repo.value)
        apply_parts(h, o, r)
        return
      end
    end

    if repository_url.changed? || canonical_slug.value.nil?
      derive_from_url
      return
    end

    if (h = host.value) && (o = owner.value) && (r = repo.value)
      apply_parts(h, o, r)
    end
  end

  private def apply_parts(h : String, o : String, r : String)
    if identity = ShardIdentity.build(h, o, r)
      apply_identity(identity)
    else
      host.add_error "#{h}/#{o}/#{r} is not a repository identity the registry can address"
    end
  end

  private def derive_from_url
    url = repository_url.value
    return if url.nil? || url.empty?

    # The rejection reason is the one ShardIdentity records on backfilled rows,
    # so a submitter and an operator reading a row see the same explanation.
    case result = ShardIdentity.analyze(url)
    in ShardIdentity::Identity
      apply_identity(result)
    in ShardIdentity::Rejection
      repository_url.add_error result.reason
    end
  end

  private def apply_identity(identity : ShardIdentity::Identity)
    host.value = identity.host
    owner.value = identity.owner
    repo.value = identity.repo
    canonical_slug.value = identity.canonical_slug
    # A row that now has an identity has no outstanding reason for lacking one.
    identity_error.value = nil
  end

  private def validate_url_format
    url = repository_url.value
    return unless url

    unless url.starts_with?("http://") || url.starts_with?("https://")
      repository_url.add_error "must be a valid URL starting with http:// or https://"
      return
    end

    # Everything stored here is fetched later by an indexer, so the host is
    # checked at save time rather than at fetch time. GitHostPolicy is
    # HostDiscovery's SSRF gate and admits only the hosts the registry
    # crawls, which means a self-hosted repository is refused here with a
    # reason rather than accepted and then silently never indexed.
    unless GitHostPolicy.safe_fetch_url?(url)
      repository_url.add_error "must be hosted on a git host the registry indexes: " \
                               "github.com, gitlab.com, bitbucket.org or codeberg.org. " \
                               "Self-hosted and private git servers cannot be indexed."
    end
  end
end
