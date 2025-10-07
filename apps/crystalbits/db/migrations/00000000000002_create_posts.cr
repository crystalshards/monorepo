class CreatePosts::V00000000000002 < Avram::Migrator::Migration::V1
  def migrate
    create table_for(Post) do
      primary_key id : Int64
      add_timestamps

      add title : String
      add slug : String
      add content : String
      add excerpt : String?
      add author_name : String
      add author_email : String?
      add tags : Array(String), default: [] of String
      add published_at : Time?
      add featured : Bool, default: false
      add view_count : Int32, default: 0
    end

    create_index table_for(Post), [:slug], unique: true, name: "posts_slug_idx"
    create_index table_for(Post), [:published_at], name: "posts_published_at_idx"
    create_index table_for(Post), [:featured], name: "posts_featured_idx"
    create_index table_for(Post), [:tags], using: :gin, name: "posts_tags_idx"
  end

  def rollback
    drop_index table_for(Post), name: "posts_tags_idx"
    drop_index table_for(Post), name: "posts_featured_idx"
    drop_index table_for(Post), name: "posts_published_at_idx"
    drop_index table_for(Post), name: "posts_slug_idx"
    drop table_for(Post)
  end
end
