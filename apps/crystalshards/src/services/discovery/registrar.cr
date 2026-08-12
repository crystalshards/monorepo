require "../shard_identity"

module Discovery
  # The one place discovery writes to the registry.
  #
  # Every write goes through ShardIdentity, so a repository is keyed on
  # host/owner/repo and a second sighting updates the row it already has rather
  # than adding another. That is the whole dedup story: there is no "have I seen
  # this before" bookkeeping in the crawler, because the identity is the key.
  #
  # Identity is also allowed to refuse. A GitLab project nested in a subgroup is
  # four path segments and cannot be addressed by a three-segment identity, so
  # it is reported as skipped with its slug rather than mangled into a row that
  # no URL can reach.
  module Registrar
    enum Outcome
      Created
      Updated
      Skipped
      Failed
    end

    record Result, outcome : Outcome, shard : Shard? = nil, detail : String? = nil

    # `name` and `description` come from the manifest the crawler just read;
    # everything else, including the star and fork counts, is whatever the
    # host's enumeration handed back with the candidate. Repository search
    # carries both counts, code search carries neither, and nil is passed
    # through as nil rather than as zero: `upsert` leaves a stored count alone
    # when the enumeration did not measure one, so the exhaustive sweep meeting
    # a row this pass created does not blank its stars.
    def self.register(repository : DiscoveredRepository, name : String, description : String?) : Result
      identity = ShardIdentity.build(repository.host, repository.owner, repository.repo)

      unless identity
        return Result.new(
          Outcome::Skipped,
          detail: "#{repository.slug} is not an identity the registry can address"
        )
      end

      existed = ShardQuery.new.canonical_slug(identity.canonical_slug).first?

      shard = ShardIdentity.upsert(
        host: repository.host,
        owner: repository.owner,
        repo: repository.repo,
        repository_url: repository.repository_url,
        name: name,
        description: description || repository.description,
        homepage_url: repository.homepage_url,
        stars: repository.stars,
        forks: repository.forks,
      )

      Result.new(existed ? Outcome::Updated : Outcome::Created, shard)
    rescue ex : ShardIdentity::InvalidIdentityError
      Result.new(Outcome::Skipped, detail: "#{repository.slug}: #{ex.message}")
    rescue ex : Avram::InvalidOperationError
      # A validation failure here is a real problem worth surfacing rather than
      # counting as a skip: the crawler believed this was a shard and the
      # registry would not store it.
      Result.new(Outcome::Failed, detail: "#{repository.slug}: #{ex.message}")
    end

    # A repository we knew about that no longer has a shard.yml, or that the host
    # no longer serves. The row stays and is marked, because download counts,
    # dependency edges and inbound links still point at it, and repositories come
    # back. Returns true when a known row was marked.
    def self.mark_unavailable(repository : DiscoveredRepository, reason : String) : Bool
      !ShardIdentity.mark_unavailable(
        host: repository.host,
        owner: repository.owner,
        repo: repository.repo,
        reason: reason
      ).nil?
    end

    def self.known?(repository : DiscoveredRepository) : Bool
      slug = ShardIdentity.slug_for(repository.host, repository.owner, repository.repo)
      return false unless slug

      !ShardQuery.new.canonical_slug(slug).first?.nil?
    end
  end
end
