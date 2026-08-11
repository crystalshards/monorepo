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
    }

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

          io << sanitize_tag(match[0], name, match[2]? || "")
        end

        io << HTML.escape(html[cursor..])
      end

      result
    end

    # An element we do not allow is escaped rather than deleted, so a doc
    # comment that talks about markup still reads correctly.
    private def self.sanitize_tag(raw : String, name : String, attributes : String) : String
      return HTML.escape(raw) unless ALLOWED_TAGS.includes?(name)

      if raw.starts_with?("</")
        return VOID_TAGS.includes?(name) ? "" : "</#{name}>"
      end

      kept = String.build do |io|
        permitted = ALLOWED_ATTRIBUTES[name]?

        if permitted
          attributes.scan(ATTR_PATTERN) do |attr|
            key = attr[1].downcase
            next unless permitted.includes?(key)

            value = attr[3]? || attr[4]? || attr[5]? || ""
            next unless safe_value?(key, value)

            io << ' ' << key << "=\"" << HTML.escape(value) << '"'
          end
        end

        # Links out of documentation open in the same tab, but must not hand
        # the destination a reference back to this window.
        io << " rel=\"nofollow noopener\"" if name == "a"
      end

      VOID_TAGS.includes?(name) ? "<#{name}#{kept}>" : "<#{name}#{kept}>"
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
  end
end
