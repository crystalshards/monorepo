class Shard < BaseModel
  table do
    column name : String
    column description : String?
    column repository_url : String
    column homepage_url : String?
    column documentation_url : String?
    column license : String?
    column total_downloads : Int64
    column github_stars : Int32?
    column github_forks : Int32?
    column last_synced_at : Time?
    column provider : String
    column repository_type : String

    # Added by migration 00000000000012. SaveShard has permitted it and
    # IndexShardWorker has written it since then; the column declaration was
    # missing, which broke every build that loaded this model.
    column readme_content : String?

    # The repository this shard is, as opposed to what it calls itself.
    # `name` is the display name from shard.yml and is not unique: two hosts
    # may each have a "router". `canonical_slug` is "host/owner/repo" and is
    # the unique key, the path in our URLs and the key on the job queue.
    #
    # These are nilable because rows predating host-qualified identity may
    # carry a repository_url that cannot be parsed into one. The backfill
    # reports those rather than guessing, and SaveShard requires identity on
    # every write from here on, so a nil identity means exactly one thing: a
    # legacy row somebody has to look at.
    column host : String?
    column owner : String?
    column repo : String?
    column canonical_slug : String?

    # Why this row has no identity, when it has none. Set by the backfill and
    # cleared the moment a usable repository_url replaces the one that could
    # not be parsed, so nobody has to guess why a shard never indexed.
    column identity_error : String?

    # Set when a crawler can no longer see the repository. The row stays:
    # download counts, dependency edges and inbound links still point at it,
    # and repositories come back.
    column unavailable_at : Time?

    has_many shard_versions : ShardVersion
    has_many dependencies : Dependency
    has_many downloads : Download
  end

  # The registry path for this shard. Legacy rows without identity fall back to
  # the name path, which is the only address they have ever had.
  def url_path : String
    if slug = canonical_slug
      "/shards/#{slug}"
    else
      "/shards/#{name}"
    end
  end

  # The registry path for one tagged version.
  #
  # nil for a legacy row with no identity: there is no host/owner/repo to
  # build the path from, and the bare-name route cannot address a version. The
  # version picker renders those versions as text rather than as links that
  # would 404.
  def version_path(version : String) : String?
    return nil unless slug = canonical_slug

    "/shards/#{slug}/versions/#{URI.encode_path_segment(version)}"
  end

  def identified? : Bool
    !canonical_slug.nil?
  end

  def unavailable? : Bool
    !unavailable_at.nil?
  end

  # "owner/repo" as the shard.yml dependency shorthand spells it.
  def repo_path : String?
    if o = owner
      if r = repo
        "#{o}/#{r}"
      end
    end
  end
end
