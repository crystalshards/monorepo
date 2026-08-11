# Gathers Crystal discussion from Reddit as raw material for our own writing.
#
# This is a research input, not a content source. Nothing it returns is ever
# stored as a post or shown to a reader. It exists so the drafting step has
# something true to write *about*, and so the draft can cite where it looked.
class RedditHarvest
  ENDPOINT   = "https://www.reddit.com"
  USER_AGENT = "crystalbits.org/0.1 (editorial harvester; +https://crystalbits.org/contribute)"

  DEFAULT_SUBREDDITS = ["crystal_programming"]
  DEFAULT_TIMEOUT    = 10.seconds

  # Subreddits that are about Crystal by definition, so their posts need no
  # further keyword test.
  CRYSTAL_SUBREDDITS = Set{"crystal_programming", "crystal_lang"}

  # For anywhere else, "crystal" alone is a mineral, a ball, and a person's
  # name. Require the language signal.
  CRYSTAL_SIGNAL = /crystal[-_ ]?lang|\bcrystal\b[^.]{0,80}\b(shard|shards|kemal|lucky|amber|compiler|macro|fiber|llvm)\b|\bkemal\b|crystal-lang\.org/i

  class FetchError < Exception
  end

  record Discussion,
    id : String,
    subreddit : String,
    title : String,
    author : String,
    permalink : String,
    score : Int32,
    comment_count : Int32,
    created_at : Time?,
    body : String do
    # What the drafting step is allowed to see. Deliberately trimmed: enough to
    # understand the subject, not enough to be tempted to paste it.
    def brief(body_limit : Int32 = 1200) : String
      String.build do |io|
        io << "Title: " << title << '\n'
        io << "Subreddit: r/" << subreddit << '\n'
        io << "Posted by: u/" << author << '\n'
        io << "Score: " << score << ", comments: " << comment_count << '\n'
        io << "URL: " << permalink << '\n'
        unless body.empty?
          io << "Author's own description (source material, never to be quoted or reused verbatim):\n"
          io << (body.size > body_limit ? body[0, body_limit] + "..." : body)
        end
      end
    end
  end

  def self.gather(
    subreddits : Array(String) = DEFAULT_SUBREDDITS,
    limit : Int32 = 25,
    timeout : Time::Span = DEFAULT_TIMEOUT,
  ) : Array(Discussion)
    new(subreddits, limit, timeout).gather
  end

  def initialize(
    @subreddits : Array(String) = DEFAULT_SUBREDDITS,
    @limit : Int32 = 25,
    @timeout : Time::Span = DEFAULT_TIMEOUT,
  )
  end

  def gather : Array(Discussion)
    seen = Set(String).new
    discussions = [] of Discussion

    @subreddits.each do |subreddit|
      listing(subreddit).each do |discussion|
        next unless crystal_related?(discussion)
        next unless seen.add?(discussion.id)
        discussions << discussion
      end
    end

    discussions.sort_by! { |discussion| -discussion.score }
    discussions
  end

  def crystal_related?(discussion : Discussion) : Bool
    return true if CRYSTAL_SUBREDDITS.includes?(discussion.subreddit.downcase)

    "#{discussion.title}\n#{discussion.body}".matches?(CRYSTAL_SIGNAL)
  end

  private def listing(subreddit : String) : Array(Discussion)
    body = get("#{ENDPOINT}/r/#{URI.encode_path_segment(subreddit)}/hot.json?limit=#{@limit}&raw_json=1")
    parse(body)
  rescue ex : FetchError
    Log.for("crystalbits.reddit").warn { "Could not read r/#{subreddit}: #{ex.message}" }
    [] of Discussion
  end

  private def parse(body : String) : Array(Discussion)
    payload = JSON.parse(body)
    children = payload["data"]?.try(&.["children"]?).try(&.as_a?)
    return [] of Discussion unless children

    children.compact_map do |child|
      data = child["data"]?
      next nil unless data

      id = data["id"]?.try(&.as_s?)
      title = data["title"]?.try(&.as_s?)
      next nil unless id && title
      next nil if data["stickied"]?.try(&.as_bool?)

      permalink = data["permalink"]?.try(&.as_s?)

      Discussion.new(
        id: id,
        subreddit: data["subreddit"]?.try(&.as_s?) || "",
        title: title,
        author: data["author"]?.try(&.as_s?) || "unknown",
        permalink: permalink ? "https://www.reddit.com#{permalink}" : (data["url"]?.try(&.as_s?) || ""),
        score: data["score"]?.try(&.as_i?) || 0,
        comment_count: data["num_comments"]?.try(&.as_i?) || 0,
        created_at: data["created_utc"]?.try(&.as_f?).try { |epoch| Time.unix(epoch.to_i) },
        body: data["selftext"]?.try(&.as_s?) || "",
      )
    end
  rescue ex : JSON::ParseException
    raise FetchError.new("Reddit returned something that is not JSON: #{ex.message}")
  end

  private def get(url : String) : String
    uri = URI.parse(url)
    client = HTTP::Client.new(uri)
    client.connect_timeout = @timeout
    client.read_timeout = @timeout

    response = begin
      client.get(uri.request_target, headers: HTTP::Headers{"User-Agent" => USER_AGENT})
    ensure
      client.close
    end

    unless response.status.success?
      raise FetchError.new("#{url} returned #{response.status_code} #{response.status.description}")
    end

    response.body
  rescue ex : FetchError
    raise ex
  rescue ex : Exception
    raise FetchError.new("could not reach #{url}: #{ex.class} #{ex.message}")
  end
end
