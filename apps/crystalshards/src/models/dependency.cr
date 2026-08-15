class Dependency < BaseModel
  table do
    column name : String
    column version_requirement : String
    column scope : String

    # The repository this dependency names, as a canonical slug, whether or not
    # the registry has a row for it.
    #
    # Distinct from dependent_shard_id, which is the row. A dependency declaring
    # `github: luislavena/radix` names one repository exactly, and it names it
    # just as precisely when radix has never been indexed here. Keeping that is
    # what makes the dependency graph a discovery source rather than only a
    # popularity signal: every unregistered slug in this column is a shard the
    # ecosystem depends on and the crawler has not found.
    #
    # NULL means the dependency names no addressable repository, which is the
    # case for an entry carrying no source key at all. A bare name is not a
    # repository: two shards may answer to it, so guessing between them would
    # put a confidently wrong slug here.
    column resolved_slug : String?

    belongs_to shard_version : ShardVersion
    belongs_to dependent_shard : Shard?
  end
end
