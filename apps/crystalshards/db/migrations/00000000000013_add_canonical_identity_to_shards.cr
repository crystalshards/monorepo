require "../../src/services/shard_identity"

# Moves a shard's identity off its name and onto the repository it comes from.
#
# Before this, `name` was unique, so a "router" on GitHub and a "router" on
# GitLab could not both be in the registry. Identity becomes host + owner +
# repo, with canonical_slug ("github.com/kemalcr/kemal") as the unique key.
# `name` stays exactly what it was, the display name from shard.yml, and keeps
# an index because search and the legacy URLs still look it up.
#
# Existing rows are backfilled by parsing their stored repository_url with
# ShardIdentity.parse_url, the same parser SaveShard uses, so the backfill and
# every write afterwards agree on what an identity is.
#
# A row whose URL cannot be parsed is left with a NULL identity and printed
# with its id, name and URL. It is not dropped and not guessed at: an
# unreachable URL, a nested group path or a name using characters outside the
# parser's accepted set is a data problem for a person to look at, and a made
# up identity would be a shard nobody can reach. Postgres treats NULLs as
# distinct in a unique index, so those rows coexist until someone fixes them.
class AddCanonicalIdentityToShards::V00000000000013 < Avram::Migrator::Migration::V1
  def migrate
    alter table_for(Shard) do
      add host : String?
      add owner : String?
      add repo : String?
      add canonical_slug : String?
      add identity_error : String?
      add unavailable_at : Time?
    end

    backfill_identities

    # The name is no longer what makes a shard unique, but it is still looked
    # up by search and by the legacy /shards/:name redirect.
    execute "DROP INDEX IF EXISTS shards_name_index;"
    execute "CREATE INDEX shards_name_index ON shards (name);"

    # Identity is the unique key now, and every lookup goes through it.
    execute "CREATE UNIQUE INDEX shards_canonical_slug_index ON shards (canonical_slug);"

    # Host listings ("everything we have from codeberg.org") read this.
    execute "CREATE INDEX shards_host_index ON shards (host);"
  end

  def rollback
    execute "DROP INDEX IF EXISTS shards_host_index;"
    execute "DROP INDEX IF EXISTS shards_canonical_slug_index;"
    execute "DROP INDEX IF EXISTS shards_name_index;"
    execute "CREATE UNIQUE INDEX shards_name_index ON shards (name);"

    alter table_for(Shard) do
      remove :host
      remove :owner
      remove :repo
      remove :canonical_slug
      remove :identity_error
      remove :unavailable_at
    end
  end

  # Reads the rows as they are now and queues one UPDATE per row whose URL
  # names a repository. The read happens while `migrate` runs, which is before
  # any queued statement executes, so it sees the pre-migration table; the
  # UPDATEs run after the ALTER, inside the migration's transaction.
  #
  # The parsing lives in ShardIdentity.backfill_plan, which SaveShard's own
  # derivation shares, so the backfill cannot disagree with what an identity
  # means everywhere else. It is covered by spec/services/backfill_spec.cr.
  private def backfill_identities
    rows = Avram.settings.database_to_migrate.query_all(
      "SELECT id, name, repository_url FROM shards ORDER BY id",
      as: {Int64, String, String}
    ).map do |(id, name, repository_url)|
      ShardIdentity::LegacyRow.new(id: id, name: name, repository_url: repository_url)
    end

    return if rows.empty?

    plan = ShardIdentity.backfill_plan(rows)
    plan.statements.each { |statement| execute statement }
    report(plan)
  end

  private def report(plan : ShardIdentity::BackfillPlan)
    puts "  identity backfill: #{plan.updated_count} of #{plan.total} shards identified"

    return if plan.unparseable.empty?

    puts "  #{plan.unparseable.size} shard(s) kept with NO identity. Each one keeps its"
    puts "  name, URL, downloads and dependency edges, stays reachable at"
    puts "  /shards/<name>, and now carries the reason in shards.identity_error."
    puts "  None can be indexed until its repository_url is corrected."

    plan.reasons.each do |reason, rows|
      puts "    #{rows.size} shard(s): #{reason}"
      rows.each do |row|
        puts "      id=#{row.id} name=#{row.name} repository_url=#{row.repository_url}"
      end
    end
  end
end
