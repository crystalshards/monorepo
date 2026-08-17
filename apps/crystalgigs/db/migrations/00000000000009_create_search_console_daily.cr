class CreateSearchConsoleDaily::V00000000000009 < Avram::Migrator::Migration::V1
  def migrate
    # Raw SQL rather than the migration DSL for one reason: `day` is a real
    # Postgres date, and the DSL maps Time to timestamptz and offers no date
    # column at all. A date is the honest type here: Search Console answers
    # in whole days, and storing a midnight timestamp would invite a reader
    # to compare it against a real timestamptz and draw a wrong conclusion.
    #
    # There is deliberately no Avram model for this table. It is written only
    # by CrystalGigs::SearchConsole's upsert and read only by the stats page,
    # both raw SQL, so a model would be a third copy of the schema to keep in
    # agreement rather than a convenience anyone uses.
    execute <<-SQL
      CREATE TABLE search_console_daily (
        id bigserial PRIMARY KEY,
        day date NOT NULL,
        query text NOT NULL,
        page text NOT NULL,
        clicks bigint NOT NULL,
        impressions bigint NOT NULL,
        position double precision NOT NULL
      )
      SQL

    # The upsert target. Search Console revises a day as its data finalizes,
    # so a later fetch of a day we already hold must replace that day's
    # numbers, never add a second row for it. This index is what makes the
    # service's INSERT ... ON CONFLICT (day, query, page) an upsert rather
    # than a unique violation.
    create_index :search_console_daily, [:day, :query, :page], unique: true
  end

  def rollback
    execute "DROP TABLE search_console_daily"
  end
end
