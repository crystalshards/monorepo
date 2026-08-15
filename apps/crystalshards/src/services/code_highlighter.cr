require "crystal/syntax_highlighter/html"
require "html"

module CrystalShards
  # Colours a fenced code block for one of the languages these pages actually
  # contain, in the eight token classes `Crystal::SyntaxHighlighter::HTML`
  # already defines: c(omment), i(nterpolation), k(eyword), m(ethod-like
  # ident), n(umber), o(perator), s(tring), t(ype/const). No language here
  # invents a class of its own, so the one theme that colours a Crystal block
  # in app.css colours a shard.yml or a shell transcript too.
  #
  # This file is copied, not shared, with
  # apps/crystaldocs/src/services/code_highlighter.cr. CrystalDocs and
  # CrystalShards build from their own Dockerfile in their own build context,
  # so neither can `path:` depend on the other's source tree the way two
  # targets in one shard.yml could; the two copies are kept identical by hand
  # instead. Change one, change both.
  module CodeHighlighter
    # Fence labels these sites actually carry. `crystal`/`cr` delegate
    # outright: `crystal docs` already runs a doc comment's Crystal blocks
    # through this exact highlighter before it writes docs.json, so a
    # README's Crystal fence gets the identical result rather than a second
    # lexer that could drift from it.
    CRYSTAL_LANGUAGES = Set{"crystal", "cr"}
    YAML_LANGUAGES    = Set{"yaml", "yml"}
    JSON_LANGUAGES    = Set{"json"}
    SHELL_LANGUAGES   = Set{"shell", "sh", "bash", "zsh"}
    SESSION_LANGUAGES = Set{"console", "shell-session"}

    # `language` is a fence's info string (or a hand-written block's own
    # label), matched case-insensitively against what these sites actually
    # contain. Anything else, including `nil` for an unlabelled fence, is
    # escaped and left alone rather than guessed at: wrong colouring reads
    # worse than none. A tokeniser that raises is caught here for the same
    # reason `highlight!` catches its own: a body that fails to read still
    # has to render as the source it is, not vanish.
    def self.highlight(source : String, language : String?) : String
      name = language.try(&.downcase)

      if CRYSTAL_LANGUAGES.includes?(name)
        Crystal::SyntaxHighlighter::HTML.highlight!(source)
      elsif YAML_LANGUAGES.includes?(name)
        highlight_yaml(source)
      elsif JSON_LANGUAGES.includes?(name)
        highlight_json(source)
      elsif SHELL_LANGUAGES.includes?(name)
        highlight_shell(source, session: false)
      elsif SESSION_LANGUAGES.includes?(name)
        highlight_shell(source, session: true)
      else
        HTML.escape(source)
      end
    rescue
      HTML.escape(source)
    end

    private def self.span(io : IO, klass : String, text : String) : Nil
      return if text.empty?
      io << %(<span class=") << klass << %(">)
      HTML.escape(text, io)
      io << "</span>"
    end

    # ---- YAML -----------------------------------------------------------

    # Read line by line rather than parsed: a `shard.yml` dependency block is
    # the single most common snippet on either site, and block style is all
    # it ever uses. A key sits at the head of a line, after its indent and
    # any sequence dashes; the value follows its colon; a comment starts
    # wherever `#` follows whitespace or opens the line. Flow collections
    # (`[a, b]`, `{a: 1}`) are not walked into: they read as plain text
    # rather than as a guess about what is inside them.
    YAML_DOCUMENT_MARKER = /\A(?:---|\.\.\.)(?=[ \t]|\z)/
    YAML_KEY             = /\A(?:"(?:[^"\\]|\\.)*"|'(?:[^']|'')*'|[^\s:#][^:#]*?):(?=[ \t]|\z)/
    YAML_QUOTED          = /\A(?:'(?:[^']|'')*'|"(?:[^"\\]|\\.)*")/
    YAML_ANCHOR_OR_ALIAS = /\A[&*][^\s,\[\]{}]+/
    YAML_NUMBER          = /\A[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?\z/
    YAML_BLOCK_SCALAR    = /\A[|>][+-]?\d*\z/
    YAML_BOOL_NULL       = Set{
      "true", "True", "TRUE", "false", "False", "FALSE",
      "yes", "Yes", "YES", "no", "No", "NO",
      "on", "On", "ON", "off", "Off", "OFF",
      "null", "Null", "NULL", "~",
    }

    private def self.highlight_yaml(source : String) : String
      String.build do |io|
        lines = source.split('\n')
        lines.each_with_index do |line, index|
          yaml_line(io, line)
          io << '\n' unless index == lines.size - 1
        end
      end
    end

    private def self.yaml_line(io : IO, line : String) : Nil
      remainder = line

      if marker = remainder[YAML_DOCUMENT_MARKER]?
        span(io, "o", marker)
        remainder = remainder[marker.size..]
      end

      # Indentation and "- " sequence markers are structure, not content:
      # their characters pass through unstyled and only advance where a key
      # or a value is allowed to start.
      loop do
        leading = remainder[/\A[ \t]*/]
        io << leading
        remainder = remainder[leading.size..]

        if remainder.starts_with?("- ")
          io << "- "
          remainder = remainder[2..]
        elsif remainder == "-"
          io << "-"
          remainder = ""
        else
          break
        end
      end

      return if remainder.empty?

      if remainder.starts_with?('#')
        span(io, "c", remainder)
        return
      end

      if key = remainder[YAML_KEY]?
        span(io, "m", key)
        remainder = remainder[key.size..]
      end

      yaml_value(io, remainder)
    end

    private def self.yaml_value(io : IO, remainder : String) : Nil
      leading = remainder[/\A[ \t]*/]
      io << leading
      remainder = remainder[leading.size..]
      return if remainder.empty?

      if remainder.starts_with?('#')
        span(io, "c", remainder)
        return
      end

      if anchor = remainder[YAML_ANCHOR_OR_ALIAS]?
        span(io, "t", anchor)
        yaml_value(io, remainder[anchor.size..])
        return
      end

      if quoted = remainder[YAML_QUOTED]?
        span(io, "s", quoted)
        yaml_trailing_comment(io, remainder[quoted.size..])
        return
      end

      # An unquoted scalar runs to a whitespace-led comment or the end of the
      # line; YAML gives a plain scalar no other terminator.
      body = remainder[/\A.*?(?=[ \t]#|\z)/]
      value = body.rstrip
      gap = body[value.size..]

      if klass = yaml_scalar_class(value)
        span(io, klass, value)
      else
        HTML.escape(value, io)
      end
      HTML.escape(gap, io)

      yaml_trailing_comment(io, remainder[body.size..])
    end

    private def self.yaml_trailing_comment(io : IO, remainder : String) : Nil
      return if remainder.empty?

      leading = remainder[/\A[ \t]*/]
      HTML.escape(leading, io)
      rest = remainder[leading.size..]
      return if rest.empty?

      if rest.starts_with?('#')
        span(io, "c", rest)
      else
        HTML.escape(rest, io)
      end
    end

    # `nil` leaves a value unstyled for the few shapes this cannot read as a
    # plain string: empty, a block-scalar header (`|`, `>-`, and the like),
    # or something that opens a flow collection this does not walk into.
    # Everything else unquoted is presumed a plain string, which is what an
    # unquoted YAML scalar always is once it is not a number, a boolean or
    # null.
    private def self.yaml_scalar_class(value : String) : String?
      return nil if value.empty?
      return nil if value.matches?(YAML_BLOCK_SCALAR)
      return "n" if value.matches?(YAML_NUMBER)
      return "k" if YAML_BOOL_NULL.includes?(value)
      return nil if "[{,".includes?(value[0])
      "s"
    end

    # ---- shell ------------------------------------------------------------

    # `console` and `shell-session` are transcripts: only a line that opens
    # with a `$ ` prompt is command syntax, and only the text after that
    # prompt is read as one. Every other line is a command's own output, and
    # colouring it as if it were input would be worse than leaving it plain:
    # this cannot tell a real command from a line of output that happens to
    # start with a word.
    PROMPT             = /\A[ \t]*\$(?=[ \t]|\z)/
    SHELL_SINGLE_QUOTE = /\A'[^']*'/
    SHELL_DOUBLE_QUOTE = /\A"(?:[^"\\]|\\.)*"/
    SHELL_WORD         = /\A[^\s|#'"]+/

    private def self.highlight_shell(source : String, session : Bool) : String
      String.build do |io|
        lines = source.split('\n')
        lines.each_with_index do |line, index|
          if session
            shell_session_line(io, line)
          else
            shell_line(io, line)
          end
          io << '\n' unless index == lines.size - 1
        end
      end
    end

    private def self.shell_session_line(io : IO, line : String) : Nil
      unless prompt = line[PROMPT]?
        HTML.escape(line, io)
        return
      end

      HTML.escape(prompt[0...-1], io)
      span(io, "o", "$")
      shell_line(io, line[prompt.size..])
    end

    private def self.shell_line(io : IO, line : String) : Nil
      remainder = line
      command_next = true

      until remainder.empty?
        if ws = remainder[/\A[ \t]+/]?
          io << ws
          remainder = remainder[ws.size..]
          next
        end

        if remainder.starts_with?('#')
          span(io, "c", remainder)
          return
        end

        if remainder.starts_with?('|')
          io << '|'
          remainder = remainder[1..]
          command_next = true
          next
        end

        if quoted = remainder[SHELL_SINGLE_QUOTE]? || remainder[SHELL_DOUBLE_QUOTE]?
          span(io, "s", quoted)
          remainder = remainder[quoted.size..]
          command_next = false
          next
        end

        if word = remainder[SHELL_WORD]?
          if word.starts_with?('-')
            span(io, "k", word)
          elsif command_next
            span(io, "m", word)
          else
            HTML.escape(word, io)
          end
          command_next = false
          remainder = remainder[word.size..]
          next
        end

        # A character none of the above claims: an unterminated quote, or
        # `&`, `;`, `<`, `>`, which this highlighter does not colour. Copied
        # through one character at a time so it cannot swallow the rest of
        # the line the way a greedy fallback would.
        HTML.escape(remainder[0].to_s, io)
        remainder = remainder[1..]
      end
    end

    # ---- JSON ---------------------------------------------------------------

    # JSON has one shape for every token, so this is the one language here
    # scanned as a whole document rather than a line at a time: a string, a
    # number, or one of the three bare literals, wherever any of them occur.
    JSON_TOKEN = /"(?:[^"\\]|\\.)*"|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?|true|false|null/

    private def self.highlight_json(source : String) : String
      String.build do |io|
        cursor = 0

        source.scan(JSON_TOKEN) do |match|
          text = match[0]
          HTML.escape(source[cursor...match.begin], io) if match.begin > cursor
          cursor = match.end

          if text.starts_with?('"')
            span(io, json_key?(source, match.end) ? "m" : "s", text)
          elsif text == "true" || text == "false" || text == "null"
            span(io, "k", text)
          else
            span(io, "n", text)
          end
        end

        HTML.escape(source[cursor..], io) if cursor < source.size
      end
    end

    # A JSON string immediately followed by `:`, skipping only whitespace, is
    # a key; every other string is a value. The two are given different
    # classes so a `"key": value` pair reads the same in JSON as it does in
    # YAML.
    private def self.json_key?(source : String, from : Int32) : Bool
      i = from
      while char = source[i]?
        return char == ':' unless char.ascii_whitespace?
        i += 1
      end
      false
    end
  end
end
