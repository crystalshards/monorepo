class ShardVersion < BaseModel
  # Where this version came from. A repository with no tags still has a default
  # branch, and representing it as a branch row is how it gets a page with a
  # manifest, dependencies and docs instead of being skipped as versionless.
  module Source
    TAG    = "tag"
    BRANCH = "branch"
  end

  table do
    column version : String
    column yanked : Bool
    column released_at : Time
    column commit_sha : String?
    column crystal_version : String?
    column metadata : JSON::Any?
    column checksum : String?

    # The git ref to check out. `version` is the normalised display string
    # ("1.12.0"); this is the ref that actually exists ("v1.12.0"), or a branch
    # name when there is no tag. Neither can be derived from the other.
    column ref : String?
    column source : String

    # The manifest as fetched, and why there is not one. Keeping the raw text
    # means a parser fix can re-read history without spending rate limit, and
    # spec_error makes "no shard.yml at this tag" a recorded fact rather than
    # something that looks identical to "not indexed yet".
    column spec_yaml : String?
    column spec_error : String?

    # The app-versus-library facts, stored rather than reduced to a boolean.
    # A library that also ships a CLI has both, and a hard classifier gets that
    # wrong in both directions without ever saying so.
    column targets : JSON::Any?
    column executables : JSON::Any?

    column indexed_at : Time?

    belongs_to shard : Shard
    has_many dependencies : Dependency
    has_many downloads : Download
  end

  # Whether this version has had its manifest fetched and parsed. Distinct from
  # "has a manifest": a tag with no shard.yml is indexed and empty, which is a
  # fact about the repository rather than a gap in the registry.
  def indexed? : Bool
    !indexed_at.nil?
  end

  # A tagged release, as opposed to the default branch standing in for one.
  # A page must not print "master" with a version badge or tell a reader to
  # depend on `version: ~> master`.
  def release? : Bool
    source == Source::TAG
  end

  # The ref to hand git. Falls back to the version string for rows written
  # before refs were recorded, which is what those rows have always used.
  def checkout_ref : String
    ref || version
  end

  # The binaries this version builds, by name. Empty for a pure library.
  def target_names : Array(String)
    targets.try(&.as_h?).try(&.keys) || [] of String
  end

  # The executables this version installs. A shard can list these without
  # declaring targets, so the two are read separately.
  def executable_names : Array(String)
    executables.try(&.as_a?).try(&.compact_map(&.as_s?)) || [] of String
  end

  # Ships something you can run, by either declaration. Deliberately not stored:
  # this is a reading of the facts, and a caller that wants to rank differently
  # reads the facts instead of inheriting someone else's threshold.
  def ships_executable? : Bool
    !target_names.empty? || !executable_names.empty?
  end
end
