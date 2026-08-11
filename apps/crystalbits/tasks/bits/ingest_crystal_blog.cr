class Bits::IngestCrystalBlog < LuckyTask::Task
  summary "Pull the official Crystal blog feed into the review queue as drafts"

  help_message <<-TEXT
    Reads #{CrystalBlogFeed::FEED_URL} and stores each entry as a DRAFT content
    item: headline, summary, author, date and link. Article bodies are not
    copied.

    Re-running is safe. Entries are deduplicated on their URL, and an existing
    item's review state is never modified, so this cannot republish something
    an editor rejected.

    Nothing this task writes is public. Approve items at /admin/moderation.
    TEXT

  def call
    outcome = CrystalBlogIngest.run

    if outcome.ok?
      puts "Crystal blog: #{outcome.summary}"
    else
      # A dead feed is a reported non-event, not a failed task. Exiting
      # non-zero here would turn crystal-lang.org having a bad afternoon into
      # a red build for us.
      puts "Crystal blog feed could not be read, nothing written."
      puts "  #{outcome.error}"
    end
  end
end
