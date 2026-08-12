class ShardVersion < BaseModel
  table do
    column version : String
    column yanked : Bool
    column released_at : Time
    column commit_sha : String?
    column crystal_version : String?
    column metadata : JSON::Any?
    column checksum : String?

    belongs_to shard : Shard
    has_many dependencies : Dependency
    has_many downloads : Download
  end

  # Whether anything has been indexed for this row.
  #
  # The registry records a version as soon as a tag is seen, and fetches the
  # manifest afterwards, so a row can exist with nothing behind it. The page
  # states that rather than drawing an empty manifest, which is the difference
  # between a sparse page and a broken one.
  #
  # SEAM: ShardIndexer is adding a `indexed_at` column that answers this
  # outright. When it lands this becomes `!indexed_at.nil?` and every caller
  # follows. Do not inline the metadata check at call sites.
  def indexed? : Bool
    !metadata.nil?
  end

  # A tagged release, as opposed to a default branch being tracked because the
  # repository publishes no tags at all. Roughly half the registry is the
  # latter, so this is the normal case and not an oddity.
  #
  # A row whose version is not a version is not a release: the crawler puts
  # the branch name in this column when there is no tag to put there. "1.12.0"
  # is a release, "master" is not, and the shape of the string says which
  # without having to guess at intent.
  #
  # SEAM: ShardIndexer is adding a `source` column holding "tag" or "branch".
  # When it lands this becomes `source == "tag"`.
  def release? : Bool
    !version.match(/\A[vV]?\d/).nil?
  end

  # What to call this row in a heading or a picker. A release keeps its
  # number; a tracked branch is named as a branch, because calling a branch
  # "v master" is how a reader ends up depending on a moving target.
  def label : String
    release? ? version : "#{version} branch"
  end
end
