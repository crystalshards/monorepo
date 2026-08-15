require "crystal/syntax_highlighter/html"
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
  #
  # A relative `src` or `href` in a README names a path in the repository
  # it was published from, not a path on this origin, so `markdown` and
  # `sanitize` also take the repository the version being read came from
  # and the ref of that version, and read a relative reference against
  # them before the scheme is checked. Both are threaded through as
  # explicit optional arguments rather than a global or a thread local: a
  # doc comment has no repository of its own, so it renders with both left
  # nil, and an already absolute reference is unaffected either way.
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
      # Highlighting. A span's class is checked against HIGHLIGHT_CLASSES and
      # a code or pre element's is rebuilt into a bare `language-` token, so
      # neither carries a name the author chose.
      "span" => Set{"class"},
      "code" => Set{"class"},
      "pre"  => Set{"class"},
    }

    # The whole vocabulary `Crystal::SyntaxHighlighter::HTML` emits: comment,
    # interpolation, keyword, ident, number, operator, string, const. The
    # compiler runs Crystal code blocks in doc comments through that exact
    # highlighter before writing docs.json, and this module runs README code
    # blocks through it too, so both surfaces arrive here speaking one
    # vocabulary and one theme styles them.
    HIGHLIGHT_CLASSES = Set{"c", "i", "k", "m", "n", "o", "s", "t"}

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

    # Markd emits a fenced block's source verbatim. The Crystal compiler does
    # not: `crystal docs` runs a Crystal block through
    # `Crystal::SyntaxHighlighter::HTML` before it writes docs.json, which is
    # why a doc comment arrives here already highlighted. A README arrives raw,
    # so it goes through the same highlighter and the two surfaces match.
    private class FenceRenderer < Markd::HTMLRenderer
      # Only a block its author labelled Crystal. The compiler treats an
      # unlabelled block as Crystal because a doc comment is Crystal by
      # context; a README's unlabelled blocks are usually shell sessions or
      # shard.yml, and the Crystal lexer would colour those as something they
      # are not.
      CRYSTAL_FENCES = Set{"crystal", "cr"}

      def code_block_body(node : Markd::Node, language : String?)
        # Chomped on both paths so a fence renders the same whatever its
        # language: the source ends in the newline before the closing fence,
        # and keeping it leaves a blank last line inside the padded block.
        code = node.text.chomp

        if language && CRYSTAL_FENCES.includes?(language.downcase)
          # `highlight!` escapes the text of every token it emits, and falls
          # back to plain escaped source when the lexer rejects the block,
          # which a snippet that elides code with `...` routinely does.
          literal(Crystal::SyntaxHighlighter::HTML.highlight!(code))
        else
          output(code)
        end
      end
    end

    # Renders a Markdown document (a README) as safe HTML.
    #
    # `repository` and `ref` place the version being rendered: the host
    # qualified slug it was published under and the version itself, which
    # is what a relative `src` or `href` in the document is read against.
    # Both default to nil, because not every caller knows a repository, and
    # nil is what makes `sanitize` leave an absolute reference alone and
    # drop a relative one rather than resolve it against nothing.
    def self.markdown(source : String?, repository : String? = nil,
                      ref : String? = nil) : String
      return "" unless source && !source.empty?

      # `Markd.to_html` hardcodes its own renderer, so the two steps it takes
      # are taken here instead to get the highlighting one.
      options = Markd::Options.new
      rendered = FenceRenderer.new(options).render(Markd::Parser.parse(source, options))
      sanitize(rendered, repository, ref)
    end

    # Cleans HTML the compiler produced from a doc comment, or a README once
    # `markdown` has rendered it to HTML. `repository` and `ref` are
    # documented on `markdown`; a doc comment reaches this method directly
    # and always leaves both nil, which is the one case a relative `src` or
    # `href` cannot be read against anything and is dropped rather than
    # resolved.
    def self.sanitize(html : String?, repository : String? = nil,
                      ref : String? = nil) : String
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
        # An anchor whose href could not be resolved is not a link to
        # anything, so its tags are dropped rather than rendered dead: the
        # words between them, which are what the author actually wrote,
        # still reach the page. A count rather than a flag, because `<a>`
        # never validly nests but nothing here stops a doc comment's raw
        # HTML from writing it that way anyway.
        unwrapping = 0

        html.scan(TAG_PATTERN) do |match|
          name = match[1].downcase
          closing = match[0].starts_with?("</")

          if inside = skipping
            skipping = nil if closing && name == inside
            cursor = match.end
            next
          end

          io << escape_text(html[cursor...match.begin])
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

          if name == "a"
            if closing
              if unwrapping > 0
                unwrapping -= 1
                next
              end
            elsif (href = attribute_value(attributes, "href")) &&
                  resolve_reference(HTML.unescape(href), "href", repository, ref).nil?
              unwrapping += 1
              next
            end
          end

          # A heading's id is derived from the text it wraps, which sits past
          # the tag being written, so it is resolved here where the rest of
          # the document is still in hand.
          anchor =
            if closing || !HEADING_TAGS.includes?(name)
              nil
            else
              resolve_anchor(html, name, attributes, cursor, taken)
            end

          io << sanitize_tag(match[0], name, attributes, anchor, repository, ref)
        end

        io << escape_text(html[cursor..])
      end

      result
    end

    # An element we do not allow is escaped rather than deleted, so a doc
    # comment that talks about markup still reads correctly.
    private def self.sanitize_tag(raw : String, name : String, attributes : String,
                                  anchor : String?, repository : String?,
                                  ref : String?) : String
      return HTML.escape(raw) unless ALLOWED_TAGS.includes?(name)

      if raw.starts_with?("</")
        return VOID_TAGS.includes?(name) ? "" : "</#{name}>"
      end

      # An image whose source could not be resolved has nothing to show.
      # Leaving a bare `<img>` with no `src` still renders a broken icon in
      # some browsers, which is the exact defect this exists to fix, so the
      # element itself is dropped instead.
      if name == "img" && (src = attribute_value(attributes, "src")) &&
         resolve_reference(HTML.unescape(src), "src", repository, ref).nil?
        return ""
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

            # Decoded before it is judged and encoded again on the way out.
            # An attribute value in the input is already entity-encoded, so
            # encoding it a second time is what turned `?a=1&b=2` in a README
            # link into a visible `&amp;`. Judging the decoded form is also
            # the stricter reading: `&#106;avascript:` is a scheme the
            # browser resolves and the encoded text is not.
            value = HTML.unescape(attr[3]? || attr[4]? || attr[5]? || "")
            value = constrain_class(name, value) if key == "class"
            next unless value

            # A relative reference is read against the repository before it
            # is judged, so the scheme check below sees exactly what a
            # reader's browser will request: either the author's own
            # absolute URL, unchanged, or the one built here in its place.
            if key == "href" || key == "src"
              value = resolve_reference(value, key, repository, ref)
              next unless value
            end

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

    # A relative `src` or `href` in a README names a path in the repository
    # it was published from, not a path on this origin, so it has no
    # meaning until it is read against that repository. `key` picks the
    # shape, because `img` wants the raw bytes at a path and `a` wants a
    # page that shows it, and GitHub, GitLab and Codeberg each spell those
    # two things differently.
    #
    # A value that already says where it goes: a same document jump, a
    # protocol relative URL, or anything with a scheme, is returned exactly
    # as given. None of those are a repository path, and the caller still
    # runs whatever this returns through the scheme allowlist afterwards,
    # which is what keeps that check meaningful either way.
    #
    # `nil` is not a parse failure, it is the answer for a reference this
    # cannot make meaningful: either there is no repository to read it
    # against, which is always true for a doc comment, or the repository is
    # on a host none of the three cases below name, and guessing at its raw
    # and blob URLs would only trade one broken link for another. The
    # caller drops whatever nil reaches rather than emit either.
    private def self.resolve_reference(value : String, key : String,
                                       repository : String?, ref : String?) : String?
      trimmed = value.strip
      return nil if trimmed.empty?
      return value if trimmed.starts_with?('#') || trimmed.starts_with?("//")
      return value if trimmed.includes?(':')
      return nil unless repository

      # Root relative and plain relative resolve the same way: both are
      # read against the repository root, so the only difference is a
      # leading slash, dropped here rather than carried into the path below.
      path = trimmed.starts_with?('/') ? trimmed[1..] : trimmed
      return nil if path.empty?

      segments = repository.split('/')
      return nil unless segments.size == 3 && segments.all?(&.presence)
      host, owner, repo = segments[0], segments[1], segments[2]

      # No default ref. Guessing at "master" reads the path against whatever
      # that branch holds today, which is a different document from the
      # version on the page, and it fails by rendering the wrong asset
      # rather than none. Every README this app renders arrives with the
      # version it was built at, so a missing ref is a defect upstream of
      # here and the reference is dropped instead of aimed somewhere.
      version = ref.presence
      return nil unless version

      case {host, key}
      when {"github.com", "src"}
        "https://raw.githubusercontent.com/#{owner}/#{repo}/#{version}/#{path}"
      when {"github.com", "href"}
        "https://github.com/#{owner}/#{repo}/blob/#{version}/#{path}"
      when {"gitlab.com", "src"}
        "https://gitlab.com/#{owner}/#{repo}/-/raw/#{version}/#{path}"
      when {"gitlab.com", "href"}
        "https://gitlab.com/#{owner}/#{repo}/-/blob/#{version}/#{path}"
      when {"codeberg.org", "src"}
        "https://codeberg.org/#{owner}/#{repo}/raw/#{version}/#{path}"
      when {"codeberg.org", "href"}
        "https://codeberg.org/#{owner}/#{repo}/src/#{version}/#{path}"
      else
        nil
      end
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

    # Text between tags in the input is already HTML: whoever produced it,
    # the compiler or Markd, encoded `&` and `<` there. Encoding it again is
    # what put a literal `&quot;` inside every code block on the site, so it
    # is decoded to the characters it stands for and encoded exactly once.
    #
    # Decoding cannot smuggle markup back in, because the encoding step that
    # follows is what decides what reaches the page, and it escapes every
    # character that could open a tag or close an attribute. A `<` that
    # TAG_PATTERN did not match, from an unterminated tag, is caught by the
    # same step whether it arrived raw or as `&lt;`.
    private def self.escape_text(text : String) : String
      HTML.escape(HTML.unescape(text))
    end

    # `class` is the one attribute whose value has to mean something to our
    # stylesheet, so it is rebuilt from a fixed vocabulary rather than
    # filtered. A span may only carry a highlighter token; a code or pre
    # element may only carry the language of its fence. Everything else is
    # dropped, so no shard author reaches a class of ours by writing one.
    private def self.constrain_class(name : String, value : String) : String?
      case name
      when "span"
        value if HIGHLIGHT_CLASSES.includes?(value)
      when "code", "pre"
        language_class(value)
      end
    end

    # Markd builds this from the fence's info string, which is whatever the
    # author typed after the backticks. Only the shape survives: one
    # `language-` token of the characters a language name is spelled with,
    # so `c++` and `objective-c` still name themselves and nothing else can.
    private def self.language_class(value : String) : String?
      return nil unless value.starts_with?("language-")

      slug = String.build do |io|
        value.lchop("language-").each_char do |char|
          io << char.downcase if char.alphanumeric? || "+#-_".includes?(char)
        end
      end

      "language-#{slug}" if slug.presence
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
