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
      # `align` is rebuilt from TABLE_ALIGNMENTS below the same way `class`
      # is rebuilt from HIGHLIGHT_CLASSES, so a table cell can carry the
      # alignment its own delimiter row asked for without a shard author
      # reaching this attribute with a value of their own choosing.
      "td" => Set{"colspan", "rowspan", "align"},
      "th" => Set{"colspan", "rowspan", "scope", "align"},
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
    # interpolation, keyword, ident, number, operator, string, const.
    # `CodeHighlighter` maps every language it colours onto this same set
    # rather than inventing one of its own, so a Crystal block from the
    # compiler, a YAML or shell or JSON fence from a README, and a `code`
    # element an author wrote by hand in a doc comment all arrive here
    # speaking one vocabulary and one theme styles them.
    HIGHLIGHT_CLASSES = Set{"c", "i", "k", "m", "n", "o", "s", "t"}

    # The only three values a GFM delimiter row's colons can produce.
    # `constrain_align` rebuilds every `align` attribute from this set, the
    # same defence in depth `constrain_class` already gives `class`.
    TABLE_ALIGNMENTS = Set{"left", "center", "right"}

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
    # so it goes through `CodeHighlighter`, which runs a Crystal fence through
    # that identical highlighter and colours a handful of other languages
    # besides, and the two surfaces match either way.
    private class FenceRenderer < Markd::HTMLRenderer
      def code_block_body(node : Markd::Node, language : String?)
        # Chomped so a fence renders the same whatever its language: the
        # source ends in the newline before the closing fence, and keeping
        # it leaves a blank last line inside the padded block.
        literal(CodeHighlighter.highlight(node.text.chomp, language))
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

      transformed, tables = extract_tables(source)

      # `Markd.to_html` hardcodes its own renderer, so the two steps it takes
      # are taken here instead to get the highlighting one.
      options = Markd::Options.new
      rendered = FenceRenderer.new(options).render(Markd::Parser.parse(transformed, options))
      rendered = splice_tables(rendered, tables, options) unless tables.empty?
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
            value = constrain_align(value) if key == "align"
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

    # `align` is the other attribute whose value has to mean something to a
    # browser rather than to whoever wrote the table: only the three values
    # a delimiter row's colons can produce survive, so no shard author
    # reaches this attribute with a fourth value of their own choosing. The
    # table markup this module builds already writes only these three, so
    # this is defence in depth rather than the only thing standing between
    # a cell and an arbitrary attribute value.
    # `String?`, not `String`, because this runs after `constrain_class`'s
    # own conditional reassignment above: `key` gates the two mutually, so
    # `value` is never actually nil by the time this executes, but the
    # compiler cannot see that across the two independent `if`s, only that
    # the value flowing in might be.
    private def self.constrain_align(value : String?) : String?
      return nil unless value
      value if TABLE_ALIGNMENTS.includes?(value)
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

    # ---- GFM tables -----------------------------------------------------

    # markd 0.5.0 has no table rule at all: `table` appears in
    # lib/markd/src/markd/rule.cr only inside the raw HTML block regex, and
    # even if an author hand wrote one, `sanitize` above is this module's
    # whole defence and would have to see it to keep it, which it never
    # gets the chance to since markd's own inline HTML handling and this
    # module's DROP_CONTENT_TAGS are not table-aware either. A README table
    # would otherwise reach the page as its delimiter row and pipes, read
    # literally, in a paragraph. This scans the raw source for a GFM table
    # before markd ever sees it, replaces each one with an unforgeable
    # placeholder line, renders the rest of the document exactly as it does
    # today, and splices the table's own HTML into the rendered placeholder
    # before the whole document reaches `sanitize`: the table this builds
    # passes through the exact same allowlist as everything else, on the
    # exact same pass, rather than being trusted on its own say-so.

    # A cell's horizontal alignment, carried by the delimiter row's leading
    # and trailing colons. `None` is the common case: no colon, no
    # attribute, a browser's own default left alignment applies.
    private enum TableAlign
      None
      Left
      Center
      Right
    end

    # What the source scan found, still unrendered Markdown. `header` and
    # each row in `rows` are exactly as many cells as GFM's own pipe
    # splitting produced, which is not necessarily `alignments.size`: a
    # short row is padded and a long one truncated against the header's own
    # count at render time, the way GFM itself does it.
    private record TableBlock,
      header : Array(String),
      alignments : Array(TableAlign),
      rows : Array(Array(String))

    # Backslash-escapable per CommonMark's own definition (the ASCII
    # punctuation ranges 0x21-0x2F, 0x3A-0x40, 0x5B-0x60, 0x7B-0x7E): what a
    # cell-splitting scan must skip as one unit, so `` `\|` `` does not end
    # its cell one character early on the backslash that precedes a
    # backtick, not a pipe.
    ESCAPABLE_PUNCTUATION = Set{
      '!', '"', '#', '$', '%', '&', '\'', '(', ')', '*', '+', ',', '-', '.',
      '/', ':', ';', '<', '=', '>', '?', '@', '[', '\\', ']', '^', '_', '`',
      '{', '|', '}', '~',
    }

    # The index of every pipe in `line` that actually ends a cell: not one
    # preceded by a single backslash, which escapes it into the cell's own
    # text instead, and not one already claimed by a two-character escape of
    # something else (`\\` escaping a backslash is what makes the pipe right
    # after it a real delimiter again).
    private def self.pipe_positions(line : String) : Array(Int32)
      positions = [] of Int32
      chars = line.chars
      i = 0
      while i < chars.size
        char = chars[i]
        if char == '\\' && i + 1 < chars.size && ESCAPABLE_PUNCTUATION.includes?(chars[i + 1])
          i += 2
        elsif char == '|'
          positions << i
          i += 1
        else
          i += 1
        end
      end
      positions
    end

    # GFM unescapes a cell's own escaped pipe before anything else touches
    # it, including before a code span's backticks get a chance to treat the
    # backslash as literal. That ordering is the only way `` `\|` `` renders
    # as `<code>|</code>` rather than `<code>\|</code>`, which is why this
    # happens here rather than being left to markd's own inline parser: a
    # code span's contents are never re-escaped once parsed.
    private def self.unescape_pipes(text : String) : String
      return text unless text.includes?('\\')
      text.gsub("\\|", "|")
    end

    # Splits one row into its cell text, GFM's own rule for what a pipe
    # delimits: a leading or trailing pipe is punctuation around the row,
    # not an empty cell of its own, so only an interior empty run (`| |`)
    # counts. `nil` is the one line shape GFM does not recognise as a row at
    # all: a bare `|`, which has nothing on either side of it to be a cell.
    private def self.split_row(line : String) : Array(String)?
      chars = line.chars
      pipes = pipe_positions(line)

      bounds = [-1] + pipes + [chars.size]
      segments = [] of String
      i = 0
      while i < bounds.size - 1
        segments << chars[(bounds[i] + 1)...bounds[i + 1]].join
        i += 1
      end

      segments.shift if pipes.first? == 0
      segments.pop if pipes.last? == chars.size - 1

      return nil if segments.empty?

      segments.map { |cell| unescape_pipes(cell).strip }
    end

    # A line the delimiter row's own grammar allows: each cell only hyphens,
    # with an optional leading or trailing colon for alignment. This
    # validates one already-split cell; `delimiter_cells` below is what
    # checks a whole candidate line and its cell count against the header.
    DELIMITER_CELL = /\A:?-+:?\z/

    # `nil` for anything that is not a delimiter row at all, including a
    # line with the right shape but indented 4 or more spaces: that is an
    # indented code block's own territory in CommonMark, table row or not.
    # A cell-count mismatch against the header is judged by the caller, not
    # here, so this only answers "is this line a delimiter row", not "is it
    # the right one".
    private def self.delimiter_cells(line : String) : Array(String)?
      return nil if indented_line?(line)
      cells = split_row(line)
      return nil unless cells
      cells.all?(&.matches?(DELIMITER_CELL)) ? cells : nil
    end

    private def self.align_of(cell : String) : TableAlign
      left = cell.starts_with?(':')
      right = cell.ends_with?(':')
      if left && right
        TableAlign::Center
      elsif left
        TableAlign::Left
      elsif right
        TableAlign::Right
      else
        TableAlign::None
      end
    end

    # A tab always reaches at least one tab stop, 4 columns, on its own.
    private def self.indented_line?(line : String) : Bool
      return true if line.starts_with?('\t')
      spaces = 0
      line.each_char do |char|
        break unless char == ' '
        spaces += 1
      end
      spaces >= 4
    end

    # A fence's own opening line: up to 3 leading spaces, then a run of 3 or
    # more backticks or tildes, the character and the run's length being all
    # a close needs to recognise later. What follows on the line, an info
    # string or nothing, plays no part in opening or closing one.
    FENCE_MARKER = /\A {0,3}(`{3,}|~{3,})/

    private def self.fence_open(line : String) : {Char, Int32}?
      return nil unless (marker = line.match(FENCE_MARKER))
      run = marker[1]
      {run[0], run.size}
    end

    private def self.fence_close?(line : String, char : Char, run : Int32) : Bool
      return false unless (marker = line.match(FENCE_MARKER))
      captured = marker[1]
      captured[0] == char && captured.size >= run && line[marker.end..].blank?
    end

    # 128 bits from the same secure generator every session token in this
    # codebase already trusts, fresh per table and never derived from the
    # document it is about to be spliced into. A README that guesses at this
    # format and writes it into its own prose is writing plain text nobody's
    # generated HTML lands inside: the odds of it matching the one made for
    # this render are the odds of guessing this number.
    private def self.generate_placeholder : String
      "crystaldocstable" + Random::Secure.hex(16)
    end

    # Scans `source` for GFM table blocks and replaces each with its own
    # placeholder line before markd ever parses it, so the rest of the
    # document renders exactly as it does today. A table is a header row
    # whose very next line is a matching delimiter row, matching in cell
    # count; a mismatch is not a table at all, GFM's own rule, and the two
    # lines are left as the ordinary text they are. Every further non-blank
    # line after the delimiter row is one more body row, GFM's own rule too,
    # until the first blank line or the end of the document ends the table.
    #
    # A header row without a pipe at all is not a table candidate, even
    # though `split_row` would happily hand back its one cell: `Foo` over
    # `---` is a setext heading, not a one-column table, and a bare `---` on
    # its own is a thematic break. Both are exactly as common in a README as
    # an actual table, and both are indistinguishable from a delimiter row
    # by shape alone. Requiring a real pipe in the header is what leaves
    # them to markd's own, correct, handling.
    #
    # What else this does not attempt: a table cannot interrupt a fenced
    # code block (tracked below, so a README documenting this very syntax
    # inside one reaches the page as the text it is), and a line that would
    # start a new block-level construct with no blank line before it, a
    # blockquote immediately after a table's last row with nothing
    # separating them, is read as one more ragged body row rather than
    # breaking the table the way GFM itself would. Real Markdown puts a
    # blank line there anyway. A table nested inside a blockquote or a list
    # is not attempted at all, the same boundary `CodeHighlighter` draws
    # around the languages it knows: this covers what a shard's README
    # actually does with a table, not the whole of GFM's own block dispatch
    # machinery.
    private def self.extract_tables(source : String) : {String, Hash(String, TableBlock)}
      return {source, {} of String => TableBlock} unless source.includes?('|')

      lines = source.split('\n')
      out = [] of String
      tables = {} of String => TableBlock
      fence : {Char, Int32}? = nil
      i = 0

      while i < lines.size
        line = lines[i]

        if open_fence = fence
          out << line
          fence = nil if fence_close?(line, open_fence[0], open_fence[1])
          i += 1
          next
        end

        if opened = fence_open(line)
          fence = opened
          out << line
          i += 1
          next
        end

        header = indented_line?(line) || pipe_positions(line).empty? ? nil : split_row(line)
        delimiter = header && i + 1 < lines.size ? delimiter_cells(lines[i + 1]) : nil

        if header && delimiter && header.size == delimiter.size
          rows = [] of Array(String)
          j = i + 2
          while j < lines.size && !lines[j].strip.empty?
            row = split_row(lines[j])
            break unless row
            rows << row
            j += 1
          end

          # A header stolen from the last line of an already open paragraph
          # needs a blank line ahead of its placeholder, or markd would fold
          # that paragraph's earlier lines into the placeholder's own
          # paragraph, and the splice below would replace them along with
          # it. GFM's real behaviour keeps the earlier lines as their own
          # paragraph, sibling to the table rather than part of it; this is
          # how that survives the round trip through a placeholder.
          out << "" if i > 0 && !lines[i - 1].strip.empty?

          placeholder = generate_placeholder
          tables[placeholder] = TableBlock.new(header, delimiter.map { |cell| align_of(cell) }, rows)
          out << placeholder
          i = j
          next
        end

        out << line
        i += 1
      end

      {out.join('\n'), tables}
    end

    # `align` is never copied from author text: only these four literals,
    # one per member of `TableAlign`, are ever written here, and `sanitize`
    # rebuilds whatever it finds through `constrain_align` again besides.
    private def self.align_attr(align : TableAlign) : String
      case align
      in .left?   then %( align="left")
      in .center? then %( align="center")
      in .right?  then %( align="right")
      in .none?   then ""
      end
    end

    # A cell's text goes through the exact inline lexer prose does, on a
    # bare paragraph node rather than through `Markd::Parser.parse`: block
    # dispatch never runs on it, so a cell that starts with `#` or `-` or
    # `>` reads as the text it is, the same as GFM's own table cells, which
    # parse inline content only and never consider a cell for block
    # structure at all. A relative `href` or `src` a cell's own markdown
    # produces is left exactly as markd wrote it, same as one written
    # anywhere else in the document: `sanitize`, run once over the whole
    # rendered page after the splice below, is what reads it against the
    # repository, not this method.
    private def self.render_cell(text : String, options : Markd::Options) : String
      return "" if text.empty?

      node = Markd::Node.new(Markd::Node::Type::Paragraph)
      node.text = text
      Markd::Parser::Inline.new(options).parse(node)

      unwrap_paragraph(FenceRenderer.new(options).render(node))
    end

    # A rendered cell is one paragraph, `<p>` to `</p>` with nothing else:
    # no attribute (`source_pos` is off), no embedded newline (cell text is
    # one source line, so it can contain no soft break), so this is exact,
    # not a heuristic.
    private def self.unwrap_paragraph(html : String) : String
      html.starts_with?("<p>") && html.ends_with?("</p>") ? html[3..-5] : html
    end

    # The table's own HTML, built directly rather than through markd:
    # nothing here is a node type markd's own renderer knows how to draw, so
    # this module owns `table`, `thead`, `tbody`, `tr`, `th` and `td`
    # outright. A short row is padded with an empty cell per the header's
    # own count, a long one's excess ignored past it, GFM's own rule for a
    # ragged body row; no `tbody` at all when there are no rows to put in
    # one, GFM's own rule for that too. Every tag and attribute name here is
    # already on ALLOWED_TAGS and ALLOWED_ATTRIBUTES, so `sanitize` keeps
    # this shape rather than stripping it once the splice below hands it
    # over.
    private def self.table_html(table : TableBlock, options : Markd::Options) : String
      String.build do |io|
        io << "<table><thead><tr>"
        table.header.each_with_index do |cell, index|
          io << "<th" << align_attr(table.alignments[index]) << '>'
          io << render_cell(cell, options)
          io << "</th>"
        end
        io << "</tr></thead>"

        unless table.rows.empty?
          io << "<tbody>"
          table.rows.each do |row|
            io << "<tr>"
            table.header.size.times do |index|
              content = row[index]? || ""
              io << "<td" << align_attr(table.alignments[index]) << '>'
              io << render_cell(content, options) unless content.empty?
              io << "</td>"
            end
            io << "</tr>"
          end
          io << "</tbody>"
        end

        io << "</table>"
      end
    end

    # Markd wrapped the lone placeholder line in a paragraph, so the whole
    # paragraph is replaced, not just the token inside it: leaving `<p>` and
    # `</p>` in place would ring every table in an empty paragraph element.
    # Each placeholder is unique to the table it names, so one substitution
    # each is exact, never a prefix of another table's own token. This runs
    # before `sanitize`, not after: the table this builds is ordinary HTML
    # to that pass, allowed through by ALLOWED_TAGS and ALLOWED_ATTRIBUTES
    # like anything else, not HTML that skips it.
    private def self.splice_tables(html : String, tables : Hash(String, TableBlock), options : Markd::Options) : String
      tables.reduce(html) do |result, (placeholder, table)|
        result.sub("<p>#{placeholder}</p>", table_html(table, options))
      end
    end
  end
end
