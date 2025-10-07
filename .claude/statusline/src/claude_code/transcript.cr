require "json"

class ClaudeCode::Transcript; end

require "./transcript/message_content"
require "./transcript/entry"

class ClaudeCode::Transcript
  include Indexable(ClaudeCode::Transcript::Entry)

  getter lines : Array(String)

  delegate size, to: @lines

  def initialize(transcript_path : String)
    initialize File.read(transcript_path).lines
  end

  def initialize(@lines : Array(String))
    @produced = 0
    @cache = Array(ClaudeCode::Transcript::Entry | Nil).new(@lines.size, nil)
  end

  def unsafe_fetch(index)
    @cache[index]? || (@cache[index] = parse(@lines[index])).not_nil!
  end

  def parse(json)
    Entry.from_json(json)
  rescue e
    STDERR.puts e.message.colorize(:red)
    STDERR.puts ""

    STDERR.puts JSON.parse(json).to_pretty_json.colorize(:red)
    STDERR.puts ""
    raise e
  end

  def reverse
    self.class.new(@lines.reverse)
  end
end
