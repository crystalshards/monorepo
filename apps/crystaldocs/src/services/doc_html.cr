require "html"
require "uri"
require "markd"

module CrystalDocs
  # Makes shard-authored documentation safe to place in our pages.
  #
  # Everything in a docs.json came from whoever published the shard. The
  # compiler renders doc comments to HTML, and a doc comment can contain any
  # markup its author typed, including a script tag. The README arrives as raw
  # Markdown, and Markdown permits inline HTML. So both are untrusted input
  # that we happen to want to display richly.
  #
  # This is an allowlist: unknown elements are dropped, and only the handful
  # of attributes that documentation genuinely needs survive. Anything not
  # explicitly permitted does not render. That direction matters, because a
  # denylist has to anticipate every vector and this only has to know what
  # documentation legitimately uses.
  module DocHtml
    # Elements documentation actually uses. Note the absence of script,
    # style, iframe, object, embed, form and friends.
    ALLOWED_TAGS = Set{
      "p", "br", "hr", "span", "div",
      "strong", "b", "em", "i", "u", "s", "del", "ins", "sub", "sup", "small",
      "code", "pre", "kbd", "samp", "var",
      "a", "img",
      "ul", "ol", "li", "dl", "dt", "dd",
      "h1", "h2", "h3", "h4", "h5", "h6",
      "blockquote", "table", "thead", "tbody", "tfoot", "tr", "th", "td",
    }

    # Per-element attribute allowlist. `href` and `src` are additionally
    # scheme-checked below, because `javascript:` is a link too.
    ALLOWED_ATTRIBUTES = {
      "a"   => Set{"href", "title"},
      "img" => Set{"src", "alt", "title"},
      "td"  => Set{"colspan", "rowspan"},
      "th"  => Set{"colspan", "rowspan", "scope"},
      # A README links to its own sections, so headings, and only headings,
      # carry an id. The value is never the author's string as written: it is
      # rebuilt in resolve_anchor before it reaches the page.
      "h1" => Set{"id"},
      "h2" => Set{"id"},
      "h3" => Set{"id"},
      "h4" => Set{"id"},
      "h5" => Set{"id"},
      "h6" => Set{"id"},
    }

    # The only elements an anchor link is given somewhere to land.
    HEADING_TAGS = Set{"h1", "h2", "h3", "h4", "h5", "h6"}

    SAFE_SCHEMES = Set{"http", "https", "mailto"}

    # Elements that never have a closing tag.
    VOID_TAGS = Set{"br", "hr", "img"}

    TAG_PATTERN  = /<\/?([A-Za-z][A-Za-z0-9]*)((?:[^>"']|"[^"]*"|'[^']*')*)\/?>/
    ATTR_PATTERN = /([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*("([^"]*)"|'([^']*)'|([^\s"'>]+))/

    # Elements whose contents are discarded along with the tag. Everything
    # here either executes or loads something.
    DROP_CONTENT_TAGS = Set{
      "script", "style", "iframe", "object", "embed", "template",
      "noscript", "form", "svg", "math",
    }

    # Renders a Markdown document (a README) as safe HTML.
    def self.markdown(source : String?) : String
      return "" unless source && !source.empty?
      sanitize(Markd.to_html(source))
    end

    # Cleans HTML the compiler produced from a doc comment.
    def self.sanitize(html : String?) : String
      return "" unless html

      # Ids have to be unique within a document, so the registry lives for a
      # single call. A README and a doc comment are separate documents.
      taken = Set(String).new

      result = String.build do |io|
        cursor = 0
        # While inside a dropped element, its text is discarded too. Removing
        # `<script>` alone would leave the code it contained sitting in the
        # page as prose, which is safe but reads like a defacement.
        skipping : String? = nil

        html.scan(TAG_PATTERN) do |match|
          name = match[1].downcase
          closing = match[0].starts_with?("</")

          if inside = skipping
            skipping = nil if closing && name == inside
            cursor = match.end
            next
          end

          io << HTML.escape(html[cursor...match.begin])
          cursor = match.end

          if DROP_CONTENT_TAGS.includes?(name)
            # Only swallow content when this element is actually closed later.
            # An unmatched `<script>` would otherwise discard the rest of the
            # document, which loses a whole doc comment over one stray tag.
            if !closing && !VOID_TAGS.includes?(name) &&
               html.index("</#{name}", cursor)
              skipping = name
            end
            next
          end

          attributes = match[2]? || ""

          # A heading's id is derived from the text it wraps, which sits past
          # the tag being written, so it is resolved here where the rest of
          # the document is still in hand.
          anchor =
            if closing || !HEADING_TAGS.includes?(name)
              nil
            else
              resolve_anchor(html, name, attributes, cursor, taken)
            end

          io << sanitize_tag(match[0], name, attributes, anchor)
        end

        io << HTML.escape(html[cursor..])
      end

      result
    end

    # An element we do not allow is escaped rather than deleted, so a doc
    # comment that talks about markup still reads correctly.
    private def self.sanitize_tag(raw : String, name : String, attributes : String,
                                  anchor : String?) : String
      return HTML.escape(raw) unless ALLOWED_TAGS.includes?(name)

      if raw.starts_with?("</")
        return VOID_TAGS.includes?(name) ? "" : "</#{name}>"
      end

      kept = String.build do |io|
        permitted = ALLOWED_ATTRIBUTES[name]?

        # Written from the resolved anchor rather than copied from the input,
        # and still gated on the allowlist, so an id cannot reach an element
        # the allowlist does not grant one to.
        if anchor && permitted.try(&.includes?("id"))
          io << " id=\"" << HTML.escape(anchor) << '"'
        end

        if permitted
          attributes.scan(ATTR_PATTERN) do |attr|
            key = attr[1].downcase
            next unless permitted.includes?(key)
            # Already written above, in its rebuilt form.
            next if key == "id"

            value = attr[3]? || attr[4]? || attr[5]? || ""
            next unless safe_value?(key, value)

            io << ' ' << key << "=\"" << HTML.escape(value) << '"'
          end
        end

        # Links out of documentation open in the same tab, but must not hand
        # the destination a reference back to this window.
        io << " rel=\"nofollow noopener\"" if name == "a"
      end

      "<#{name}#{kept}>"
    end

    # `href` and `src` are the two attributes that can execute script, so the
    # scheme is checked rather than the text.
    private def self.safe_value?(key : String, value : String) : Bool
      return true unless key == "href" || key == "src"

      trimmed = value.strip
      return false if trimmed.empty?
      # Relative and anchor links carry no scheme and are fine.
      return true if trimmed.starts_with?('#') || trimmed.starts_with?('/')
      return true unless trimmed.includes?(':')

      scheme = trimmed.split(':').first.downcase
      SAFE_SCHEMES.includes?(scheme)
    end

    # The id a heading answers to. An author who wrote one by hand keeps it,
    # subject to the same character constraint as a generated one; otherwise
    # it is the GitHub slug of the heading's own text.
    #
    # Markd puts no id on a heading. Its only anchor scheme is the optional
    # toc renderer, which is off here and which writes a separate
    # `<a id="anchor-<percent-encoded title>">` beside the heading rather than
    # on it. No README author wrote their links against that. They wrote them
    # against GitHub, so GitHub's convention is the one that makes the links
    # already sitting in these files resolve.
    private def self.resolve_anchor(html : String, name : String, attributes : String,
                                    cursor : Int32, taken : Set(String)) : String?
      declared = constrain_id(attribute_value(attributes, "id"), downcase: false)
      base = declared || constrain_id(heading_text(html, name, cursor), downcase: true)
      return nil unless base

      unique_id(base, taken)
    end

    # GitHub's slug and the character constraint in one pass: letters and
    # digits survive, hyphen and underscore survive, whitespace becomes a
    # hyphen, everything else is dropped without leaving a separator behind.
    # That last detail is why "Usage & Setup" is "usage--setup" here exactly
    # as it is on GitHub, and why a link written against GitHub lands.
    #
    # Rebuilding rather than screening is what makes the value safe. A quote,
    # an angle bracket or a backslash has nothing to survive as, however it
    # arrived or was encoded, so no heading can close the attribute or open a
    # tag. Escaping at the point of writing is then belt and braces.
    private def self.constrain_id(text : String?, downcase : Bool) : String?
      return nil unless text

      String.build do |io|
        text.each_char do |char|
          if char.alphanumeric?
            io << (downcase ? char.downcase : char)
          elsif char == '-' || char == '_'
            io << char
          elsif char.whitespace?
            io << '-'
          end
        end
      end.presence
    end

    # GitHub numbers repeats rather than dropping them, so a second "Usage"
    # answers to #usage-1 and a link to it still works.
    private def self.unique_id(base : String, taken : Set(String)) : String
      candidate = base
      counter = 0

      while taken.includes?(candidate)
        counter += 1
        candidate = "#{base}-#{counter}"
      end

      taken << candidate
      candidate
    end

    # The text a heading wraps, with nested markup removed, so
    # "## The `parse` method" slugs on its words rather than on its tags.
    private def self.heading_text(html : String, name : String, cursor : Int32) : String?
      close = html.index(/<\/#{name}[\s>]/i, cursor)
      return nil unless close

      HTML.unescape(html[cursor...close].gsub(TAG_PATTERN, ""))
    end

    # The raw value of one attribute, before any constraint is applied.
    private def self.attribute_value(attributes : String, key : String) : String?
      attributes.scan(ATTR_PATTERN) do |attr|
        return attr[3]? || attr[4]? || attr[5]? || "" if attr[1].downcase == key
      end

      nil
    end
  end
end
