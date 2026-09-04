require "json"
require "./host_text"

# Everything indexing needs to render a shard page, as one value.
#
# This is a snapshot rather than a set of getters because the whole point of
# the redesign is that a shard is fetched once per pass. A provider that can
# answer all of this in one request should not be asked five times, and a
# provider that cannot should still hand back the same shape.
#
# Nothing here is defaulted to a falsy stand-in. `stars` nil means the fetch
# did not produce a star count; it never means zero. That distinction is the
# difference between "nobody uses this" and "we have not looked yet", and the
# registry's ranking depends on being able to tell them apart.
class RepositorySnapshot
  # One ref worth indexing, with what the host already told us about it.
  #
  # `ref` is what git checks out ("v1.12.0", or "master" for an untagged
  # repository). `version` is the normalised display string ("1.12.0"). Neither
  # derives from the other: a tag may or may not carry the v, and a branch is
  # not a version at all.
  struct Ref
    getter ref : String
    getter version : String
    getter source : String
    getter commit_sha : String?
    getter committed_at : Time?

    def initialize(
      @ref : String,
      @version : String,
      @source : String = ShardVersion::Source::TAG,
      @commit_sha : String? = nil,
      @committed_at : Time? = nil,
    )
    end

    def tag? : Bool
      source == ShardVersion::Source::TAG
    end

    # A tag conventionally carries a leading v that the registry does not
    # store. Branches are left exactly as the host spells them.
    def self.from_tag(name : String, commit_sha : String? = nil, committed_at : Time? = nil) : Ref
      normalised = name.starts_with?('v') && name.size > 1 && name[1].ascii_number? ? name.lchop('v') : name

      new(
        ref: name,
        version: normalised,
        source: ShardVersion::Source::TAG,
        commit_sha: commit_sha,
        committed_at: committed_at,
      )
    end

    def self.from_branch(name : String, commit_sha : String? = nil, committed_at : Time? = nil) : Ref
      new(
        ref: name,
        version: name,
        source: ShardVersion::Source::BRANCH,
        commit_sha: commit_sha,
        committed_at: committed_at,
      )
    end
  end

  getter stars : Int32?
  getter forks : Int32?
  getter description : String?
  getter homepage : String?
  getter license : String?
  getter topics : Array(String)
  getter default_branch : String?
  getter pushed_at : Time?
  getter archived : Bool?

  # Newest first. Empty is a real answer: plenty of shards have never tagged.
  getter refs : Array(Ref)

  # Every free-text field here was written by the repository's author and is
  # bound for a Postgres text column, so each is scrubbed on the way in for the
  # same reason a fetched file is. See HostText.
  def initialize(
    @stars : Int32? = nil,
    @forks : Int32? = nil,
    description : String? = nil,
    homepage : String? = nil,
    license : String? = nil,
    topics : Array(String) = [] of String,
    default_branch : String? = nil,
    @pushed_at : Time? = nil,
    @archived : Bool? = nil,
    @refs : Array(Ref) = [] of Ref,
  )
    @description = HostText.scrub(description)
    @homepage = HostText.scrub(homepage)
    @license = HostText.scrub(license)
    @topics = HostText.scrub(topics)
    @default_branch = HostText.scrub(default_branch)
  end

  def tags : Array(Ref)
    refs.select(&.tag?)
  end

  # The ref a page shows by default: the newest tag, or the default branch when
  # there is no tag. Nil only when the host told us nothing at all, which is a
  # failed fetch rather than an untagged repository.
  def primary_ref : Ref?
    refs.first?
  end

  # The default-branch ref, synthesised when the host reported a branch name but
  # no tags. Kept separate from `refs` construction so a provider only has to
  # report the facts it has.
  def self.branch_ref(default_branch : String?, pushed_at : Time?) : Ref?
    return nil unless (branch = default_branch) && !branch.empty?

    Ref.from_branch(branch, committed_at: pushed_at)
  end
end
