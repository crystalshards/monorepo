# The stats_rollups claim table, present in this suite only.
#
# The table belongs to the page views collector's migration, which is a
# separate slice of the analytics work and does not exist in this branch.
# SearchConsole claims its daily fetch through that table, so its specs need
# it here, created idempotently with exactly the columns the cross-slice
# contract pins: name, covered_through, claimed_at, last_error. Once the
# collector's migration lands this CREATE becomes a no-op and the migration
# owns the schema.
#
# Registered before every example rather than at require time because the
# test database is created and migrated by the setup files, which run after
# the support files load.
module SearchConsoleClaimTable
  def self.ensure! : Nil
    # Column for column the collector's final DDL, so this suite runs
    # against the same shape the merged migration will own.
    AppDatabase.exec <<-SQL
      CREATE TABLE IF NOT EXISTS stats_rollups (
        id bigserial PRIMARY KEY,
        name text NOT NULL UNIQUE,
        covered_through date,
        claimed_at timestamptz,
        last_error text
      )
      SQL
  end
end

Spec.before_each do
  SearchConsoleClaimTable.ensure!
end
