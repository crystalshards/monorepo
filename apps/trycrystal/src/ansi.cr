# The compiler talks in ANSI.
#
# Crystal's compiler writes its diagnostics with SGR escape sequences: dim for
# the gutter, bold for the offending source, bold green for the caret, bold
# yellow for the error line. Rendered as text, which is the only way this app
# renders anything a sandbox produced, those sequences arrive on the page as
# literal noise:
#
#   [2m 2 |  [22m[1mIO.gets [22m
#           [32;1m^--- [39;22m
#   [33;1mError: undefined method 'gets' for IO.class [39;22m
#
# So the escapes are parsed HERE, in Crystal, into a list of segments that each
# carry text and the classes to draw it with. Three reasons this is server side
# rather than in the browser:
#
#   It is real parsing with real edge cases, and `crystal spec` can test it.
#   The browser's job in this app is to render strings and author none, which
#     is the rule that keeps a code-execution console from growing an XSS hole.
#     A segment list is rendered with createElement plus textContent, so no
#     markup is ever built from compiler output.
#   Unknown and dangerous sequences are DROPPED here rather than reaching the
#     page. A cursor-movement or screen-clear sequence is meaningless in a div
#     and printing it raw is how the noise above happened.
module Ansi
  ESC = '\e'

  # One run of text that shares a style. `classes` is a space separated list of
  # CSS class names, empty when the run is unstyled, and is composed here from
  # a closed set: nothing a compiler emits can invent a class name.
  record Segment, text : String, classes : String do
    def to_json(json : JSON::Builder)
      json.object do
        json.field "text", text
        json.field "classes", classes
      end
    end
  end

  # Foreground colors 30-37 and their bright forms 90-97. Named rather than
  # numbered in the CSS so the palette stays in the stylesheet's token blocks,
  # where the art direction lives, instead of being decided here.
  COLORS = {
    30 => "black", 31 => "red", 32 => "green", 33 => "yellow",
    34 => "blue", 35 => "magenta", 36 => "cyan", 37 => "white",
    90 => "black", 91 => "red", 92 => "green", 93 => "yellow",
    94 => "blue", 95 => "magenta", 96 => "cyan", 97 => "white",
  }

  # Parses text containing SGR sequences into styled segments.
  #
  # Returns a single unstyled segment for plain text, and an empty array for
  # empty input, so a caller can treat the result uniformly.
  def self.parse(text : String) : Array(Segment)
    return [] of Segment if text.empty?

    segments = [] of Segment
    buffer = String::Builder.new
    bold = false
    dim = false
    color = nil.as(String?)

    flush = -> do
      body = buffer.to_s
      unless body.empty?
        segments << Segment.new(body, classes(bold, dim, color))
      end
      buffer = String::Builder.new
    end

    reader = Char::Reader.new(text)
    while reader.has_next?
      char = reader.current_char

      # Only CSI sequences are understood: ESC [ ... final-byte. Anything else
      # beginning with ESC is dropped up to and including its final byte,
      # because a lone escape in a div is noise at best.
      if char == ESC && reader.peek_next_char == '['
        reader.next_char # [
        params = String::Builder.new
        final = nil.as(Char?)

        while reader.has_next?
          reader.next_char
          break unless reader.has_next?
          c = reader.current_char
          # Parameter and intermediate bytes, then a final byte in @ to ~.
          if c.ascii_number? || c == ';' || c == ':' || c == '?'
            params << c
          else
            final = c
            break
          end
        end

        # 'm' is SGR, the only sequence that means anything here. Everything
        # else (cursor moves, erasures) is consumed and discarded.
        if final == 'm'
          flush.call
          bold, dim, color = apply(params.to_s, bold, dim, color)
        end

        reader.next_char if reader.has_next?
        next
      end

      # An escape that is not the start of a CSI sequence: a truncated stream
      # (a killed submission can be cut mid-sequence) or a two-character
      # escape. Drop the escape byte itself rather than letting it through,
      # because a raw escape reaching the page through textContent is the
      # exact defect this parser exists to fix.
      if char == ESC
        reader.next_char if reader.has_next?
        next
      end

      buffer << char
      reader.next_char
    end

    flush.call
    segments
  end

  # Applies one SGR parameter list to the current style.
  #
  # An empty parameter list means reset, which is what a bare "\e[m" is.
  private def self.apply(params : String, bold : Bool, dim : Bool, color : String?)
    codes = params.split(';').map { |part| part.to_i? || 0 }
    codes = [0] if codes.empty?

    # An index walk rather than each, because 38 and 48 carry their own
    # parameters (38;5;n for the 256 palette, 38;2;r;g;b for truecolor) and
    # reading those as codes would turn "38;5;200" into a stray style. The
    # compiler does not use them; a hostile submission printing raw escapes
    # can, so they are consumed and ignored rather than misread.
    index = 0
    while index < codes.size
      code = codes[index]
      case code
      when 0  then bold, dim, color = false, false, nil
      when 1  then bold = true
      when 2  then dim = true
      when 22 then bold, dim = false, false
      when 39 then color = nil
      when 38, 48
        # Skip the selector and its arguments: 5 takes one, 2 takes three.
        selector = codes[index + 1]?
        index += selector == 2 ? 4 : (selector == 5 ? 2 : 1)
        next
      else
        if named = COLORS[code]?
          color = named
        end
      end
      index += 1
    end

    {bold, dim, color}
  end

  private def self.classes(bold : Bool, dim : Bool, color : String?) : String
    parts = [] of String
    parts << "ansi-bold" if bold
    parts << "ansi-dim" if dim
    parts << "ansi-#{color}" if color
    parts.join(' ')
  end

  # True when the text carries any escape sequence at all. Used to decide
  # whether a segment list is worth sending alongside the plain string.
  def self.styled?(text : String) : Bool
    text.includes?(ESC)
  end
end
