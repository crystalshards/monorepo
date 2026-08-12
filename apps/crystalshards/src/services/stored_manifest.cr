# A presenter over the manifest a version already has stored.
#
# Distinct from ShardManifest, which parses raw shard.yml during indexing and
# is the producer of this data. This is the reader: it takes the JSON already
# on a ShardVersion and answers the questions a page asks, which are not the
# questions an indexer asks. They shared a name until the indexer landed, and
# only one of them can have it.
require "json"

# The shard.yml as it stood on one git tag.
#
# IndexShardWorker parses the manifest and stores it verbatim in
# shard_versions.metadata, so this is a reader over that column rather than a
# second copy of the data.
#
# It exists because shard.yml is a stranger's file. Every key in it is
# optional, the registry is full of minimal manifests, and a page that calls
# `.as_h` on whatever somebody committed crashes on the first shard that
# wrote `dependencies:` with nothing under it. So every accessor here answers
# with an empty result instead of raising, and the page renders the emptiness
# as a statement rather than as a blank.
class StoredManifest
  # One entry under `targets:`.
  struct Target
    getter name : String
    getter main : String?

    def initialize(@name : String, @main : String?)
    end
  end

  # nil means "no manifest is indexed for this version", which is a different
  # thing from "the manifest declares nothing", and the page says so
  # differently. A metadata blob that parsed to something other than a mapping
  # is equally unusable and is also nil: a shard.yml that is a bare list is
  # not a manifest, whatever the file was called.
  def self.from(version : ShardVersion?) : StoredManifest?
    return nil unless version

    raw = version.metadata
    return nil unless raw

    fields = raw.as_h?
    return nil unless fields

    new(fields)
  end

  def initialize(@fields : Hash(String, JSON::Any))
  end

  # The `crystal:` constraint. Written as a string most of the time, but
  # `crystal: 0.36` is legal YAML and arrives as a number, so both are read.
  def crystal : String?
    scalar("crystal")
  end

  def license : String?
    scalar("license")
  end

  def version : String?
    scalar("version")
  end

  def description : String?
    scalar("description")
  end

  def authors : Array(String)
    strings("authors")
  end

  def executables : Array(String)
    strings("executables")
  end

  # `targets:` is a mapping of executable name to build settings, of which
  # `main` is the only one worth showing.
  def targets : Array(Target)
    mapping("targets").map do |name, spec|
      main = spec.as_h?.try { |h| json_scalar(h["main"]?) }
      Target.new(name, main)
    end
  end

  def dependency_names : Array(String)
    mapping("dependencies").keys
  end

  def development_dependency_names : Array(String)
    mapping("development_dependencies").keys
  end

  # Where a dependency comes from, in the shorthand shard.yml itself uses:
  # "github: kemalcr/kemal", "git: https://example.com/x.git", "path: ../y".
  #
  # This is the part of a dependency the Dependency row does not carry, and it
  # is the part that says whether a requirement tracks a release or somebody's
  # branch. Refs are appended for the same reason: "github: foo/bar,
  # branch: master" is a materially different dependency from a versioned one.
  def source_for(name : String) : String?
    spec = dependency_spec(name)
    return nil unless spec

    parts = [] of String

    SOURCE_KEYS.each do |key|
      if value = json_scalar(spec[key]?)
        parts << "#{key}: #{value}"
        break
      end
    end

    REF_KEYS.each do |key|
      if value = json_scalar(spec[key]?)
        parts << "#{key}: #{value}"
      end
    end

    parts.empty? ? nil : parts.join(", ")
  end

  # True when the manifest was indexed but says nothing a reader would want:
  # a name and a version and no more. Most of the registry looks like this,
  # and the page states it rather than drawing an empty table.
  def describes_nothing? : Bool
    crystal.nil? &&
      license.nil? &&
      authors.empty? &&
      executables.empty? &&
      targets.empty? &&
      dependency_names.empty? &&
      development_dependency_names.empty?
  end

  # The source keys `shards` understands, in the order it resolves them.
  SOURCE_KEYS = %w[github gitlab bitbucket codeberg git hg fossil path]

  # What a source is pinned to, when it is pinned to something other than a
  # version requirement.
  REF_KEYS = %w[branch tag commit]

  private def dependency_spec(name : String) : Hash(String, JSON::Any)?
    spec = mapping("dependencies")[name]? || mapping("development_dependencies")[name]?
    spec.try(&.as_h?)
  end

  private def scalar(key : String) : String?
    json_scalar(@fields[key]?)
  end

  # YAML scalars arrive as whatever JSON type they parsed to. A number is
  # still worth showing; a mapping or a list under a key that should hold a
  # scalar is malformed, and showing nothing beats showing a JSON dump.
  private def json_scalar(value : JSON::Any?) : String?
    return nil unless value

    case raw = value.raw
    when String
      raw.blank? ? nil : raw
    when Int64, Float64, Bool
      raw.to_s
    else
      nil
    end
  end

  # `authors:` is a list, but a single author written as a bare string is
  # common enough that reading it as a one-item list is kinder than dropping
  # the only author a shard has.
  private def strings(key : String) : Array(String)
    value = @fields[key]?
    return [] of String unless value

    case raw = value.raw
    when Array
      raw.compact_map { |entry| json_scalar(entry) }
    when String
      raw.blank? ? [] of String : [raw]
    else
      [] of String
    end
  end

  private def mapping(key : String) : Hash(String, JSON::Any)
    @fields[key]?.try(&.as_h?) || {} of String => JSON::Any
  end
end
