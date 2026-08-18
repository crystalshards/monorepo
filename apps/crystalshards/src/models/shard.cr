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

    # Repository facts, fetched by indexing rather than by discovery.
    #
    # Every one of these is nilable and NULL means "not fetched yet", never
    # zero and never false. A permanent 0 star count reads as "nobody uses
    # this", which is a different and wrong claim from "we have not looked".
    # An empty array is a real answer meaning the repository declares no topics,
    # so it cannot double as "we have not looked". Hence nilable, like the rest.
    column topics : Array(String)?
    column default_branch : String?
    column pushed_at : Time?
    column archived : Bool?

    # The version a page shows by default, denormalised so a list of shards
    # costs one query rather than one per row. Rewritten on every indexing
    # pass from the version rows, so it cannot drift from them.
    column latest_version : String?

    # The indexing cursor, kept on the row rather than in a side table.
    #
    #   index_attempted_at  claimed, written before any fetch
    #   indexed_at          finished successfully
    #   index_error         finished and failed, with the reason
    #
    # Attempted set with both others nil is a pass that died mid-shard. That
    # row is visibly incomplete, sorts to the back of the queue rather than
    # blocking its head, and is retried on a later pass.
    column indexed_at : Time?
    column index_attempted_at : Time?
    column index_error : String?

    # Where a running index pass has got to. Written by `ShardIndexer` around
    # each step and cleared when the pass finishes either way, so it is only
    # ever meaningful while a pass is actually running.
    column index_step : String?

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
    Shard.url_path(name, canonical_slug)
  end

  # The same rule, for a caller holding the two columns rather than a row.
  # The typeahead reads only name and canonical_slug, because loading a whole
  # shard per suggestion is a page of models to render eight links, and the
  # link it renders has to be the one this row would render for itself.
  def self.url_path(name : String, canonical_slug : String?) : String
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
