class AddPrefixSearchIndexesToShards::V00000000000017 < Avram::Migrator::Migration::V1
  # The masthead field suggests as the reader types, so its query runs on
  # keystrokes and has to be answered from an index. Nothing on this table
  # could answer it.
  #
  # `shards_name_index` is a plain btree on `name`, and a plain btree cannot
  # serve a prefix match unless the database collates in C. These databases
  # collate in en_US.utf8, so `name LIKE 'kem%'` is a sequential scan, and
  # `name ILIKE 'kem%'` is a sequential scan under any collation because the
  # index holds the original case. Measured on crystalshards_development with
  # enable_seqscan off, which prices a sequential scan at 1e10: the planner
  # still chose one for `name LIKE 'kem%'`, for `name ILIKE 'kem%'` and for
  # `lower(name) LIKE 'kem%'`. It had nothing else to choose.
  #
  # These two make it choose otherwise. Indexing `lower(...)` is what makes
  # the match case-insensitive without ILIKE, and `text_pattern_ops` is what
  # makes a prefix comparison an index range: the operator class compares
  # character by character rather than by collation rules, so Postgres can
  # rewrite `LIKE 'kem%'` into `>= 'kem' AND < 'ken'` and walk the tree. With
  # both in place the same statement plans as a BitmapOr over both indexes.
  #
  # Only prefixes, deliberately. An infix match ('%kem%') cannot use a btree
  # at all and would need pg_trgm, an extension that requires a superuser to
  # install and that this schema has never asked for. A prefix is also the
  # right semantic for a typeahead: it ranks what the reader is part way
  # through typing, rather than every row that happens to contain those
  # letters. The full search behind the Enter key still matches anywhere.
  def migrate
    execute <<-SQL
      CREATE INDEX shards_name_prefix_index
        ON shards (lower(name) text_pattern_ops)
      SQL

    execute <<-SQL
      CREATE INDEX shards_canonical_slug_prefix_index
        ON shards (lower(canonical_slug) text_pattern_ops)
      SQL
  end

  def rollback
    execute "DROP INDEX IF EXISTS shards_canonical_slug_prefix_index"
    execute "DROP INDEX IF EXISTS shards_name_prefix_index"
  end
end
