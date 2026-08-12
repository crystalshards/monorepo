require "yaml"
require "json"

# A parsed shard.yml, or the reason there is not one.
#
# Parsing is separated from fetching so the whole of it is exercised by specs
# with no network, and so a malformed manifest produces a recorded sentence
# rather than an exception that aborts a shard mid-index.
#
# Every error string here is written to `shard_versions.spec_error` and rendered
# verbatim to a reader, so they are sentences about the repository rather than
# exception class names.
struct ShardManifest
  getter name : String?
  getter version : String?
  getter crystal : String?
  getter license : String?
  getter description : String?
  getter homepage : String?
  getter documentation : String?
  getter dependencies : JSON::Any?
  getter development_dependencies : JSON::Any?
  getter targets : JSON::Any?
  getter executables : JSON::Any?

  # The whole manifest as JSON, which is what `shard_versions.metadata` has
  # always held and what UpdateDependenciesWorker reads.
  getter document : JSON::Any

  def initialize(
    @document : JSON::Any,
    @name : String? = nil,
    @version : String? = nil,
    @crystal : String? = nil,
    @license : String? = nil,
    @description : String? = nil,
    @homepage : String? = nil,
    @documentation : String? = nil,
    @dependencies : JSON::Any? = nil,
    @development_dependencies : JSON::Any? = nil,
    @targets : JSON::Any? = nil,
    @executables : JSON::Any? = nil,
  )
  end

  # Parsed, or a sentence saying why not. Never raises: a shard whose manifest
  # is broken is a shard with a broken manifest, which is a fact worth showing,
  # not a reason to abandon the rest of its indexing.
  def self.parse(source : String) : ShardManifest | String
    if source.blank?
      return "shard.yml is empty."
    end

    parsed = YAML.parse(source)

    # A YAML document can legally be a string, a list, or null. Only a mapping
    # is a shard.yml, and "false" is a valid YAML document that would otherwise
    # sail through as a manifest with no fields.
    mapping = parsed.as_h?
    unless mapping
      return "shard.yml is valid YAML but not a mapping, so it is not a shard specification."
    end

    document = JSON.parse(parsed.to_json)

    new(
      document: document,
      name: string_at(document, "name"),
      version: string_at(document, "version"),
      crystal: crystal_constraint(document),
      license: string_at(document, "license"),
      description: string_at(document, "description"),
      homepage: string_at(document, "homepage"),
      documentation: string_at(document, "documentation"),
      dependencies: mapping_at(document, "dependencies"),
      development_dependencies: mapping_at(document, "development_dependencies"),
      targets: mapping_at(document, "targets"),
      executables: list_at(document, "executables"),
    )
  rescue ex : YAML::ParseException
    # The line number is the useful half of this: a reader with it can open the
    # file and see the problem.
    location = ex.line_number > 0 ? " at line #{ex.line_number}" : ""
    "shard.yml is not valid YAML#{location}: #{ex.message.to_s.split(" at line").first}."
  rescue ex : JSON::Error
    "shard.yml parsed as YAML but could not be represented as JSON: #{ex.message}."
  end

  # The binaries this version builds, by name.
  def target_names : Array(String)
    targets.try(&.as_h?).try(&.keys) || [] of String
  end

  def executable_names : Array(String)
    executables.try(&.as_a?).try(&.compact_map(&.as_s?)) || [] of String
  end

  # `crystal:` is a version constraint, but it is written both as a string
  # (">= 1.0.0") and, in older shards, as a bare number that YAML reads as a
  # float (crystal: 0.35). Both mean the same thing to a reader.
  private def self.crystal_constraint(document : JSON::Any) : String?
    value = document["crystal"]?
    return nil unless value

    case raw = value.raw
    when String then raw.presence
    when Int64  then raw.to_s
    when Float64
      # 0.35 must not render as "0.35000000000000003".
      raw == raw.round ? raw.to_i64.to_s : raw.to_s
    end
  end

  private def self.string_at(document : JSON::Any, key : String) : String?
    document[key]?.try(&.as_s?).presence
  end

  private def self.mapping_at(document : JSON::Any, key : String) : JSON::Any?
    value = document[key]?
    return nil unless value.try(&.as_h?)

    value
  end

  private def self.list_at(document : JSON::Any, key : String) : JSON::Any?
    value = document[key]?
    return nil unless value.try(&.as_a?)

    value
  end
end
