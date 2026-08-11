class Bits::GenerateDrafts < LuckyTask::Task
  summary "Draft original write-ups of community discussion into the review queue"

  help_message <<-TEXT
    Gathers Crystal discussion from Reddit, asks the configured model to write
    an original summary of each, and stores the result as a DRAFT marked
    machine_drafted with its sources attached.

    Requires both:
      BITS_MODEL_API_KEY   model API credential
      BITS_MODEL           model identifier

    With either missing the task reports that generation is off and writes
    nothing. There is no placeholder mode and no default credential.

    Reddit text is never republished. Drafts that reproduce a run of
    #{DraftGenerator::VERBATIM_WORD_RUN} consecutive words from their source
    are discarded before storage.

    Nothing this task writes is public. Approve items at /admin/moderation.
    TEXT

  def call
    result = DraftGenerator.run

    puts result.message

    result.drafts.each do |draft|
      puts "  #{draft.title}"
      puts "    /news/#{draft.slug} (state: #{draft.state})"
      draft.source_urls.each { |url| puts "    source: #{url}" }
    end
  end
end
