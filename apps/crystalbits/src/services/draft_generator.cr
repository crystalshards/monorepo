# Writes our own summaries of community discussion when nobody has contributed.
#
# Three things about this are deliberate.
#
# It is off unless configured. No API key and no model name means the generator
# reports that it is unconfigured and writes nothing at all: no placeholder
# rows, no lorem text, no empty draft that looks like it ran. Off is a state
# you can see, not a silent no-op.
#
# It never republishes. The model is given Reddit threads as material and told
# to write original prose about them. What it produces is checked for verbatim
# reuse before anything is stored.
#
# It cannot publish. Drafts land in the same DRAFT state as everything else and
# are marked machine_drafted, which the pages render as a visible label.
class DraftGenerator
  Habitat.create do
    # No default. A missing key is the off switch, and defaulting a credential
    # in code is how a placeholder ends up in production.
    setting api_key : String? = nil

    # No default either. Guessing a model identifier produces a runtime 404
    # that looks like an outage; naming it is part of turning the feature on.
    setting model : String? = nil

    setting api_base : String = "https://api.anthropic.com/v1/messages"
    setting api_version : String = "2023-06-01"
    setting max_drafts_per_run : Int32 = 2
    setting max_tokens : Int32 = 2000
    setting request_timeout : Time::Span = 90.seconds
  end

  ATTRIBUTION = "Written by CrystalBits from public community discussion, then reviewed by an editor before publication."

  LICENSE_NOTE = "Original text written for CrystalBits. The discussions it draws on " \
                 "belong to their authors and are linked rather than reproduced."

  # A generated draft that repeats a long run of its source verbatim is not a
  # summary, it is a copy with extra steps. Anything at or above this many
  # consecutive words lifted from the material is rejected before storage.
  VERBATIM_WORD_RUN = 12

  enum Status
    Generated
    NotConfigured
    NoMaterial
    Failed
  end

  record Result,
    status : Status,
    drafts : Array(ContentItem),
    message : String do
    def generated? : Bool
      status.generated?
    end

    def configured? : Bool
      !status.not_configured?
    end
  end

  # True only when every piece of runtime configuration the generator needs is
  # present. Pages and tasks ask this rather than inspecting env vars.
  def self.configured? : Bool
    !settings.api_key.nil? && !settings.model.nil?
  end

  def self.missing_configuration : Array(String)
    missing = [] of String
    missing << "BITS_MODEL_API_KEY" if settings.api_key.nil?
    missing << "BITS_MODEL" if settings.model.nil?
    missing
  end

  def self.run(
    subreddits : Array(String) = RedditHarvest::DEFAULT_SUBREDDITS,
    limit : Int32? = nil,
  ) : Result
    new(subreddits, limit || settings.max_drafts_per_run).run
  end

  def initialize(
    @subreddits : Array(String) = RedditHarvest::DEFAULT_SUBREDDITS,
    @limit : Int32 = DraftGenerator.settings.max_drafts_per_run,
  )
  end

  def run : Result
    api_key = DraftGenerator.settings.api_key
    model = DraftGenerator.settings.model

    if api_key.nil? || model.nil?
      missing = DraftGenerator.missing_configuration
      verb = missing.size == 1 ? "is" : "are"
      return inert("Machine drafting is off: #{missing.join(" and ")} #{verb} not set. No drafts were written.")
    end

    discussions = RedditHarvest.gather(@subreddits)

    # Anything already written up is not material. This is the same
    # deduplication guarantee the feed gets: a second run is not a second copy.
    fresh = discussions.reject { |discussion| already_written_up?(discussion) }

    if fresh.empty?
      return Result.new(
        status: Status::NoMaterial,
        drafts: [] of ContentItem,
        message: "Found #{discussions.size} Crystal discussions, all of which already have a draft. Nothing written.",
      )
    end

    drafts = [] of ContentItem
    failures = [] of String

    fresh.first(@limit).each do |discussion|
      begin
        drafts << draft_for(discussion, api_key, model, fresh)
      rescue ex : Exception
        failures << "#{discussion.permalink}: #{ex.message}"
        Log.for("crystalbits.generator").warn { "Draft failed for #{discussion.permalink}: #{ex.message}" }
      end
    end

    if drafts.empty?
      return Result.new(
        status: Status::Failed,
        drafts: drafts,
        message: "No drafts written. #{failures.join("; ")}",
      )
    end

    Result.new(
      status: Status::Generated,
      drafts: drafts,
      message: "Wrote #{drafts.size} machine-drafted item(s) to the review queue" \
               "#{failures.empty? ? "" : ", #{failures.size} failed"}.",
    )
  end

  private def inert(message : String) : Result
    Log.for("crystalbits.generator").info { message }
    Result.new(status: Status::NotConfigured, drafts: [] of ContentItem, message: message)
  end

  private def already_written_up?(discussion : RedditHarvest::Discussion) : Bool
    ContentItemQuery.new.by_source_url(discussion.permalink).any?
  end

  private def draft_for(
    discussion : RedditHarvest::Discussion,
    api_key : String,
    model : String,
    pool : Array(RedditHarvest::Discussion),
  ) : ContentItem
    related = pool.reject { |other| other.id == discussion.id }.first(3)
    written = request_draft(discussion, related, api_key, model)

    reject_verbatim!(written.body, [discussion] + related)

    sources = ([discussion.permalink] + related.map(&.permalink) + written.sources).uniq

    item, _ = ContentIngestor.upsert(
      source_url: discussion.permalink,
      origin: ContentItem::Origin::GENERATED,
      title: written.title,
      summary: written.summary,
      body: written.body,
      attribution: ATTRIBUTION,
      original_author: "CrystalBits (machine-drafted)",
      original_published_at: Time.utc,
      license_note: LICENSE_NOTE,
      machine_drafted: true,
      source_urls: sources,
    )

    item
  end

  private record Written,
    title : String,
    summary : String,
    body : String,
    sources : Array(String)

  private def request_draft(
    discussion : RedditHarvest::Discussion,
    related : Array(RedditHarvest::Discussion),
    api_key : String,
    model : String,
  ) : Written
    payload = {
      model:      model,
      max_tokens: DraftGenerator.settings.max_tokens,
      system:     SYSTEM_PROMPT,
      messages:   [{role: "user", content: user_prompt(discussion, related)}],
    }

    response = post_json(DraftGenerator.settings.api_base, payload, api_key)
    parse_written(response)
  end

  SYSTEM_PROMPT = <<-PROMPT
    You write short news items for CrystalBits, a blog about the Crystal
    programming language.

    You are given Reddit threads as raw material. They are research, not copy.

    Rules, in order of importance:
    1. Never reproduce sentences or phrases from the material. Write your own
       prose from your own understanding of what happened. If you cannot say
       something in your own words, leave it out.
    2. Only state things the material supports. No invented benchmarks,
       version numbers, quotes or names.
    3. Link out. Refer readers to the projects and threads rather than
       retelling them in full.
    4. Attribute people and projects by name where the material names them.
    5. Plain, specific, unhyped prose. No marketing register. No em-dashes.

    Reply with a single JSON object and nothing else:
    {
      "title": "under 80 characters, specific, no clickbait",
      "summary": "one or two sentences, under 240 characters",
      "body": "markdown, 150 to 350 words, with inline links to the sources",
      "sources": ["every URL you relied on"]
    }
    PROMPT

  private def user_prompt(
    discussion : RedditHarvest::Discussion,
    related : Array(RedditHarvest::Discussion),
  ) : String
    String.build do |io|
      io << "Write an original CrystalBits item about this discussion.\n\n"
      io << "PRIMARY MATERIAL\n"
      io << discussion.brief << "\n\n"

      unless related.empty?
        io << "OTHER RECENT THREADS, for context only:\n"
        related.each { |other| io << "- " << other.title << " (" << other.permalink << ")\n" }
        io << '\n'
      end

      io << "Remember: your own words, cite the links, say only what the material supports."
    end
  end

  private def post_json(url : String, payload, api_key : String) : String
    uri = URI.parse(url)
    client = HTTP::Client.new(uri)
    client.connect_timeout = DraftGenerator.settings.request_timeout
    client.read_timeout = DraftGenerator.settings.request_timeout

    response = begin
      client.post(
        uri.request_target,
        headers: HTTP::Headers{
          "content-type"      => "application/json",
          "x-api-key"         => api_key,
          "anthropic-version" => DraftGenerator.settings.api_version,
        },
        body: payload.to_json,
      )
    ensure
      client.close
    end

    unless response.status.success?
      raise "model API returned #{response.status_code}: #{response.body[0, 300]}"
    end

    response.body
  end

  private def parse_written(response_body : String) : Written
    envelope = JSON.parse(response_body)

    text = envelope["content"]?.try(&.as_a?).try(&.compact_map { |block|
      block["text"]?.try(&.as_s?)
    }.join("\n"))

    raise "model response had no text content" if text.nil? || text.empty?

    json = extract_json_object(text)
    raise "model did not return a JSON object" unless json

    parsed = JSON.parse(json)

    title = parsed["title"]?.try(&.as_s?).try(&.strip)
    summary = parsed["summary"]?.try(&.as_s?).try(&.strip)
    body = parsed["body"]?.try(&.as_s?).try(&.strip)

    raise "model response was missing title, summary or body" if title.nil? || summary.nil? || body.nil?
    raise "model returned an empty draft" if title.empty? || body.empty?

    sources = parsed["sources"]?.try(&.as_a?).try(&.compact_map(&.as_s?)) || [] of String

    Written.new(title: title, summary: summary, body: body, sources: sources)
  rescue ex : JSON::ParseException
    raise "could not parse the model response as JSON: #{ex.message}"
  end

  # Models sometimes wrap JSON in prose or a fenced block. Take the outermost
  # brace-balanced object rather than trusting the whole reply to be clean.
  private def extract_json_object(text : String) : String?
    start = text.index('{')
    return nil unless start

    depth = 0
    in_string = false
    escaped = false

    (start...text.size).each do |i|
      char = text[i]

      if in_string
        if escaped
          escaped = false
        elsif char == '\\'
          escaped = true
        elsif char == '"'
          in_string = false
        end
        next
      end

      case char
      when '"' then in_string = true
      when '{' then depth += 1
      when '}'
        depth -= 1
        return text[start..i] if depth.zero?
      end
    end

    nil
  end

  # The last line of defence against republishing. Compares word runs rather
  # than whole strings, because the failure we care about is a paragraph lifted
  # from a thread, not an unavoidable shared phrase like "garbage collector".
  private def reject_verbatim!(body : String, sources : Array(RedditHarvest::Discussion)) : Nil
    draft_words = normalize_words(body)
    return if draft_words.size < VERBATIM_WORD_RUN

    draft_runs = Set(String).new
    (0..draft_words.size - VERBATIM_WORD_RUN).each do |i|
      draft_runs << draft_words[i, VERBATIM_WORD_RUN].join(' ')
    end

    sources.each do |source|
      source_words = normalize_words("#{source.title}\n#{source.body}")
      next if source_words.size < VERBATIM_WORD_RUN

      (0..source_words.size - VERBATIM_WORD_RUN).each do |i|
        run = source_words[i, VERBATIM_WORD_RUN].join(' ')
        if draft_runs.includes?(run)
          raise "draft reproduced #{VERBATIM_WORD_RUN} consecutive words from #{source.permalink}, discarded"
        end
      end
    end
  end

  private def normalize_words(text : String) : Array(String)
    text.downcase.gsub(/[^a-z0-9\s]/, " ").split(/\s+/).reject(&.empty?)
  end
end
