# WORKAROUND for Avram 1.4.2 bug with nilable columns
# This file patches Avram to use nilable_eq for nilable columns
# Issue: Avram generates .eq() for all columns, even nilable ones
# Solution: Override the generated query methods for all nilable columns

# Patch Dependency model
class Dependency::BaseQuery
  def dependent_shard_id(value : Int64?)
    nilable_eq(:dependent_shard_id, value)
  end
end

# Patch Shard model
class Shard::BaseQuery
  def description(value : String?)
    nilable_eq(:description, value)
  end

  def homepage_url(value : String?)
    nilable_eq(:homepage_url, value)
  end

  def documentation_url(value : String?)
    nilable_eq(:documentation_url, value)
  end

  def license(value : String?)
    nilable_eq(:license, value)
  end

  def github_stars(value : Int32?)
    nilable_eq(:github_stars, value)
  end

  def github_forks(value : Int32?)
    nilable_eq(:github_forks, value)
  end

  def last_synced_at(value : Time?)
    nilable_eq(:last_synced_at, value)
  end
end

# Patch ShardVersion model
class ShardVersion::BaseQuery
  def commit_sha(value : String?)
    nilable_eq(:commit_sha, value)
  end

  def crystal_version(value : String?)
    nilable_eq(:crystal_version, value)
  end

  def metadata(value : JSON::Any?)
    nilable_eq(:metadata, value)
  end

  def checksum(value : String?)
    nilable_eq(:checksum, value)
  end
end

# Patch Download model
class Download::BaseQuery
  def ip_address(value : String?)
    nilable_eq(:ip_address, value)
  end

  def user_agent(value : String?)
    nilable_eq(:user_agent, value)
  end

  def country_code(value : String?)
    nilable_eq(:country_code, value)
  end
end
