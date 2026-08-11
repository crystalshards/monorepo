# The single place third-party text becomes HTML in CrystalBits.
#
# Contribution bodies, Crystal blog summaries and machine-drafted copy are all
# untrusted. None of them may reach a page through `raw` without passing
# through here first. Mirrors CrystalDocs::DocHtml, which does the same job for
# README markdown in the docs app.
module BitsHtml
  # Tags we will emit. Anything else is unwrapped: the element disappears and
  # its text survives, which is the right outcome for a stray <div> and for a
  # <marquee> alike.
  ALLOWED_TAGS = Set{
    "p", "br", "hr", "em", "i", "strong", "b", "code", "pre", "blockquote",
    "ul", "ol", "li", "dl", "dt", "dd", "a", "img",
    "h1", "h2", "h3", "h4", "h5", "h6",
    "table", "thead", "tbody", "tfoot", "tr", "th", "td",
    "del", "ins", "sup", "sub", "span", "figure", "figcaption",
  }

  # Dropped along with everything inside them. Unwrapping a <script> would
  # spill its source into the page as visible text; unwrapping an <iframe>
  # would strip the one thing making it inert.
  OPAQUE_TAGS = Set{
    "script", "style", "iframe", "object", "embed", "applet",
    "noscript", "template", "svg", "math", "frame", "frameset",
    "form", "input", "button", "select", "textarea", "option",
  }

  VOID_TAGS = Set{"br", "hr", "img"}

  # Attributes are allowlisted per tag rather than globally, so that a `src`
  # permitted on <img> cannot ride in on some other element.
  ALLOWED_ATTRS = {
    "a"   => Set{"href", "title"},
    "img" => Set{"src", "alt", "title"},
    "td"  => Set{"colspan", "rowspan"},
    "th"  => Set{"colspan", "rowspan", "scope"},
    "ol"  => Set{"start"},
  }

  ALLOWED_SCHEMES = Set{"http", "https", "mailto"}

  # Enough of the entity table to defeat the encodings used to smuggle a scheme
  # separator past a naive check: `javascript&colon;alert(1)` and friends.
  NAMED_ENTITIES = {
    "colon"   => ":",
    "tab"     => "\t",
    "newline" => "\n",
    "amp"     => "&",
    "lt"      => "<",
    "gt"      => ">",
    "quot"    => "\"",
    "apos"    => "'",
    "sol"     => "/",
    "nbsp"    => " ",
  }

  ENTITY_PATTERN  = /&(#[0-9]+|#[xX][0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]*);?/
  SURROGATE_RANGE = (0xD800..0xDFFF)

  private record Token,
    name : String,
    attributes : Array({String, String}),
    closing : Bool,
    self_closing : Bool,
    comment : Bool,
    end_pos : Int32 do
    def closing?
      closing
    end

    def self_closing?
      self_closing
    end

    def comment?
      comment
    end
  end

  # Untrusted Markdown to display HTML.
  #
  # Markd's safe mode replaces every raw HTML block and inline HTML run with a
  # comment, and blanks javascript:, vbscript:, file: and data: destinations on
  # links and images. What comes out is markup Markd generated itself. We still
  # run it through `sanitize`, because this is the one string in the app handed
  # to `raw` and a single bug in one library should not be enough to put a
  # script tag on a page.
  def self.markdown(source : String) : String
    sanitize(Markd.to_html(source, Markd::Options.new(safe: true, gfm: true)))
  end

  # Untrusted HTML to display HTML, by allowlist.
  #
  # Unknown elements are unwrapped, script-bearing elements are dropped whole,
  # attributes not named for their tag are removed, and unbalanced tags are
  # closed so a malformed fragment cannot swallow the rest of the page.
  def self.sanitize(html : String) : String
    String.build do |io|
      open_tags = [] of String
      pos = 0

      while pos < html.size
        lt = html.index('<', pos)

        unless lt
          io << html[pos..]
          break
        end

        io << html[pos...lt]
        token = read_tag(html, lt)

        unless token
          # A '<' that begins nothing tag-shaped is content, not markup.
          io << "&lt;"
          pos = lt + 1
          next
        end

        pos = token.end_pos
        next if token.comment?

        name = token.name

        if OPAQUE_TAGS.includes?(name)
          pos = skip_to_close(html, name, pos) unless token.closing? || token.self_closing?
          next
        end

        next unless ALLOWED_TAGS.includes?(name)

        if token.closing?
          # Close everything opened inside the element too, so an out-of-order
          # close cannot leave a dangling open tag behind.
          if idx = open_tags.rindex(name)
            (open_tags.size - 1).downto(idx) { |i| io << "</" << open_tags[i] << ">" }
            open_tags.delete_at(idx, open_tags.size - idx)
          end
          next
        end

        io << '<' << name
        write_attributes(io, name, token.attributes)
        io << '>'

        if VOID_TAGS.includes?(name)
          # No closing tag, nothing to track.
        elsif token.self_closing?
          # HTML ignores the slash on a non-void element, so an input of
          # `<span/>` would otherwise open a span nothing ever closes.
          io << "</" << name << '>'
        else
          open_tags << name
        end
      end

      open_tags.reverse_each { |open| io << "</" << open << '>' }
    end
  end

  # Third-party HTML reduced to text.
  #
  # Feed summaries arrive as HTML we did not write and only ever appear as a
  # short blurb beside a link out. Reducing them to text removes the whole
  # markup risk class: the result is rendered with `text`, never `raw`.
  def self.plain_text(html : String, limit : Int32? = nil) : String
    stripped = sanitize(html)
      .gsub(/<(br|hr)\s*\/?>/i, " ")
      .gsub(/<\/(p|div|li|h[1-6]|tr|blockquote|dd|dt|figcaption)>/i, " ")
      .gsub(/<[^>]*>/, "")

    text = decode_entities(stripped).gsub(/\s+/, " ").strip

    return text unless limit
    return text if text.size <= limit

    cut = text[0, limit]
    boundary = cut.rindex(' ')
    trimmed = boundary && boundary > limit // 2 ? cut[0, boundary] : cut
    trimmed.rstrip(" \t\n.,;:-") + "..."
  end

  private def self.comment_token(end_pos : Int32) : Token
    Token.new("", [] of {String, String}, false, false, true, end_pos)
  end

  # Reads one tag starting at `start`, which must point at a '<'. Returns nil
  # when what follows is not a tag, so the caller can treat the '<' as text.
  private def self.read_tag(html : String, start : Int32) : Token?
    if html[start, 4]? == "<!--"
      close = html.index("-->", start + 4)
      return comment_token(close ? close + 3 : html.size)
    end

    marker = html[start + 1]?
    if marker == '!' || marker == '?'
      close = html.index('>', start + 1)
      return comment_token(close ? close + 1 : html.size)
    end

    pos = start + 1
    closing = false

    if html[pos]? == '/'
      closing = true
      pos += 1
    end

    first = html[pos]?
    return nil unless first && first.ascii_letter?

    name_start = pos
    while (ch = html[pos]?) && (ch.ascii_alphanumeric? || ch == '-')
      pos += 1
    end
    name = html[name_start...pos].downcase

    attributes = [] of {String, String}
    self_closing = false

    loop do
      pos = skip_whitespace(html, pos)
      ch = html[pos]?
      break unless ch

      if ch == '>'
        pos += 1
        break
      end

      if ch == '/'
        if html[pos + 1]? == '>'
          self_closing = true
          pos += 2
          break
        end
        pos += 1
        next
      end

      attr_start = pos
      while (c = html[pos]?) && !c.ascii_whitespace? && c != '=' && c != '>' && c != '/'
        pos += 1
      end

      if pos == attr_start
        pos += 1
        next
      end

      attr_name = html[attr_start...pos].downcase
      pos = skip_whitespace(html, pos)
      value = ""

      if html[pos]? == '='
        pos += 1
        pos = skip_whitespace(html, pos)
        quote = html[pos]?

        if quote == '"' || quote == '\''
          pos += 1
          value_start = pos
          while (c = html[pos]?) && c != quote
            pos += 1
          end
          value = html[value_start...pos]
          pos += 1 if html[pos]?
        else
          value_start = pos
          while (c = html[pos]?) && !c.ascii_whitespace? && c != '>'
            pos += 1
          end
          value = html[value_start...pos]
        end
      end

      attributes << {attr_name, value}
    end

    Token.new(name, attributes, closing, self_closing, false, pos)
  end

  private def self.skip_whitespace(html : String, pos : Int32) : Int32
    while (ch = html[pos]?) && ch.ascii_whitespace?
      pos += 1
    end
    pos
  end

  # Everything from here to the element's own closing tag goes in the bin.
  private def self.skip_to_close(html : String, name : String, from : Int32) : Int32
    search = from

    while (lt = html.index('<', search))
      if html[lt + 1]? == '/'
        token = read_tag(html, lt)
        return token.end_pos if token && token.closing? && token.name == name
      end
      search = lt + 1
    end

    html.size
  end

  private def self.write_attributes(io : IO, tag_name : String, attributes : Array({String, String})) : Nil
    allowed = ALLOWED_ATTRS[tag_name]?
    return unless allowed

    seen = Set(String).new

    attributes.each do |pair|
      name, value = pair
      next unless allowed.includes?(name)
      next unless seen.add?(name)
      next if (name == "href" || name == "src") && !safe_url?(value)

      io << ' ' << name << "=\"" << escape_attribute(value) << '"'
    end
  end

  # A relative or fragment URL is fine. An absolute one has to use a scheme we
  # named. Anything else loses the attribute outright rather than being
  # escaped, because an escaped `javascript:` URL still runs when clicked.
  private def self.safe_url?(value : String) : Bool
    url = value.strip
    return false if url.empty?

    probe = decode_entities(url).gsub(/[[:space:]\x00-\x1f]/, "").downcase
    colon = probe.index(':')
    return true unless colon

    # A colon appearing after the first '/', '?' or '#' belongs to the path or
    # query, not to a scheme: "docs/a:b" is a relative URL, not a protocol.
    {probe.index('/'), probe.index('?'), probe.index('#')}.each do |marker|
      return true if marker && marker < colon
    end

    ALLOWED_SCHEMES.includes?(probe[0...colon])
  end

  # Escapes a bare '&' but leaves an existing entity alone, so a URL query of
  # "?a=1&amp;b=2" does not come out as "&amp;amp;b=2".
  private def self.escape_attribute(value : String) : String
    value
      .gsub(/&(?!#?[0-9A-Za-z]+;)/, "&amp;")
      .gsub('"', "&quot;")
      .gsub('<', "&lt;")
      .gsub('>', "&gt;")
  end

  private def self.decode_entities(value : String) : String
    return value unless value.includes?('&')

    value.gsub(ENTITY_PATTERN) do |match, captures|
      body = captures[1]

      if body.starts_with?('#')
        digits = body[1..]
        code = if digits.starts_with?('x') || digits.starts_with?('X')
                 digits[1..].to_i?(16)
               else
                 digits.to_i?
               end

        if code && code > 0 && code <= 0x10FFFF && !SURROGATE_RANGE.includes?(code)
          code.chr.to_s
        else
          match
        end
      else
        NAMED_ENTITIES[body.downcase]? || match
      end
    end
  end
end
