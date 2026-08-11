class CreateContentItems::V00000000000004 < Avram::Migrator::Migration::V1
  def migrate
    create table_for(ContentItem) do
      primary_key id : Int64
      add_timestamps

      # Where the item came from: a human submission, the Crystal blog feed, or
      # our own machine drafting. All three land in the same table because they
      # go through the same review, and a reviewer should not have to remember
      # which queue a thing lives in.
      add origin : String
      add state : String

      add title : String
      add slug : String
      add body : String?
      add summary : String?

      # Provenance. Every item carries these whatever its origin, so that
      # nothing can be published without a reader being able to see where it
      # came from and under what terms.
      add source_url : String?
      add original_author : String?
      add original_published_at : Time?
      add attribution : String
      add license_note : String?

      add machine_drafted : Bool, default: false
      add source_urls : Array(String), default: [] of String

      # Submitter contact is operational, not editorial. It is never rendered.
      add submitter_contact : String?
      add canonical_url : String?

      add reviewed_at : Time?
      add reviewed_by : String?
      add review_note : String?
    end

    create_index table_for(ContentItem), [:slug], unique: true, name: "content_items_slug_idx"
    create_index table_for(ContentItem), [:state], name: "content_items_state_idx"
    create_index table_for(ContentItem), [:origin], name: "content_items_origin_idx"

    # The deduplication guarantee. Postgres treats NULLs as distinct in a unique
    # index, so contributions (which have no source URL) are unaffected, while
    # a second ingestion run cannot insert a second copy of a feed entry or a
    # second write-up of the same discussion.
    execute <<-SQL
      CREATE UNIQUE INDEX content_items_source_url_idx
      ON content_items (source_url)
      WHERE source_url IS NOT NULL
    SQL
  end

  def rollback
    execute "DROP INDEX IF EXISTS content_items_source_url_idx"
    drop_index table_for(ContentItem), name: "content_items_origin_idx"
    drop_index table_for(ContentItem), name: "content_items_state_idx"
    drop_index table_for(ContentItem), name: "content_items_slug_idx"
    drop table_for(ContentItem)
  end
end
