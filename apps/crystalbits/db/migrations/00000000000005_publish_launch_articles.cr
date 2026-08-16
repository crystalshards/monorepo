# The four launch announcements, one per property.
#
# Content arrives through a migration because these four posts are what makes
# the site non-empty on the day it opens, and the deploy's migration step is
# the only path that reaches production without someone running a task by hand
# against the live database. It inserts once and does nothing on a slug that
# already exists, so editing a post in the database afterwards is safe: this
# never runs again to clobber it.
#
# The prose lives in db/articles/*.md rather than inside this file, read at
# compile time. Two reasons. A heredoc cannot hold flush left prose, and
# indenting the bodies to satisfy it would turn every paragraph into a
# markdown code block. And an article is text a person edits and reviews, so
# it belongs in a file a diff can show plainly rather than buried in SQL.
#
# Dollar quoting rather than escaping, so a body can contain apostrophes and
# quotation marks without a layer of doubling nobody can proofread. The tag is
# checked below rather than assumed: a body that happened to contain it would
# end the literal early and change the statement.
class PublishLaunchArticles::V00000000000005 < Avram::Migrator::Migration::V1
  BODY_TAG = "$article$"

  ARTICLES = [
    {
      slug:    "finding-every-crystal-shard",
      title:   "Finding every Crystal shard",
      excerpt: "Crystal has never had one place that knows what exists. The original CrystalShards crawled the git hosts instead of waiting for submissions, and that is running again.",
      tag:     "crystalshards",
      body:    {{ read_file("#{__DIR__}/../articles/finding-every-crystal-shard.md") }},
    },
    {
      slug:    "documentation-for-every-shard",
      title:   "Documentation for every shard",
      excerpt: "Crystal documentation is published by whoever wrote the library, if they publish it at all. CrystalDocs builds it for every shard, links across projects, and hosts the standard library alongside them.",
      tag:     "crystaldocs",
      body:    {{ read_file("#{__DIR__}/../articles/documentation-for-every-shard.md") }},
    },
    {
      slug:    "where-crystal-work-gets-posted",
      title:   "Where Crystal work gets posted",
      excerpt: "A board for Crystal roles, posted by the people doing the hiring. Indexable as jobs, and honest about which ones are still open.",
      tag:     "crystalgigs",
      body:    {{ read_file("#{__DIR__}/../articles/where-crystal-work-gets-posted.md") }},
    },
    {
      slug:    "a-place-to-write-about-crystal",
      title:   "A place to write about Crystal",
      excerpt: "The posts here today are ours, announcing our own sites. The point of CrystalBits is everyone else: how you are using Crystal, what you learned, and what you shipped.",
      tag:     "crystalbits",
      body:    {{ read_file("#{__DIR__}/../articles/a-place-to-write-about-crystal.md") }},
    },
  ]

  def migrate
    ARTICLES.each_with_index do |article, index|
      body = article[:body]

      # A body carrying the dollar quote tag would close the literal early and
      # leave the rest of the article being read as SQL. It cannot happen with
      # the four files in the tree, which is exactly why it is worth catching
      # here rather than discovering it on a fifth.
      raise "Article #{article[:slug]} contains the dollar quote tag" if body.includes?(BODY_TAG)

      # Published a few minutes apart, oldest first, so the feed has a stable
      # order rather than four rows sharing one timestamp and sorting however
      # the planner feels.
      minutes_ago = (ARTICLES.size - index) * 5

      execute <<-SQL
      INSERT INTO posts
        (title, slug, content, excerpt, author_name, tags, published_at, featured, view_count, created_at, updated_at)
      VALUES (
        #{BODY_TAG}#{article[:title]}#{BODY_TAG},
        #{BODY_TAG}#{article[:slug]}#{BODY_TAG},
        #{BODY_TAG}#{body}#{BODY_TAG},
        #{BODY_TAG}#{article[:excerpt]}#{BODY_TAG},
        #{BODY_TAG}The Bushido Collective#{BODY_TAG},
        ARRAY[#{BODY_TAG}announcements#{BODY_TAG}, #{BODY_TAG}#{article[:tag]}#{BODY_TAG}],
        NOW() - INTERVAL '#{minutes_ago} minutes',
        false,
        0,
        NOW(),
        NOW()
      )
      ON CONFLICT (slug) DO NOTHING
      SQL
    end
  end

  # Removes only the four rows this migration introduced, by the slugs it
  # wrote. A post someone published later is not this migration's to delete.
  def rollback
    slugs = ARTICLES.map { |article| "#{BODY_TAG}#{article[:slug]}#{BODY_TAG}" }.join(", ")
    execute "DELETE FROM posts WHERE slug IN (#{slugs})"
  end
end
