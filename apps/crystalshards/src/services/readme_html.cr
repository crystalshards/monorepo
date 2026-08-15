require "markd"

module CrystalShards
  # Makes a shard's README safe to place on its detail page.
  #
  # A README is Markdown written by whoever published the shard, and Markdown
  # permits raw HTML, so it is untrusted input in exactly the way a doc
  # comment is for `CrystalDocs::DocHtml`. This module does not copy that
  # allowlist sanitiser, on purpose: a second hand-rolled tag allowlist here
  # is a second thing to keep in sync with the first as either one drifts, and
  # markd already proves the property we need without one.
  #
  # `Markd::Options#safe?`, when true, does not merely escape raw HTML, it
  # drops it: a raw HTML block or an inline HTML span is replaced with an
  # HTML comment rather than rendered (at the pinned v0.5.0,
  # lib/markd/src/markd/renderers/html_renderer.cr:165 and :171). The same
  # flag also drops the `href`/`src` of a link or image whose destination
  # matches `javascript:`, `vbscript:`, `file:` or a non-image `data:` URI
  # (html_renderer.cr:113 and :144, checked against `Rule::UNSAFE_PROTOCOL` in
  # lib/markd/src/markd/rule.cr:73-74) rather than passing it through.
  # Everything markd writes from README text, it also HTML-escapes
  # (`Renderer#escape` in lib/markd/src/markd/renderer.cr). Safe mode plus
  # that escaping is the same property DocHtml exists to add by hand, so this
  # module turns it on and leans on it instead.
  #
  # What this module adds on top is repository-relative URL resolution, which
  # DocHtml has no need for: a doc comment never references a path in the
  # shard's own tree, and a README routinely does (`![Logo](docs/logo.png)`).
  module ReadmeHtml
    # Markd emits a fenced block's source verbatim, safe mode included:
    # nothing in a code fence is markup, it is source somebody wants to
    # read, and the base renderer merely escapes it. `CodeHighlighter` is
    # the module `CrystalDocs`'s own README renderer runs a fence through
    # too, so a Crystal, YAML, shell or JSON block reads the same on either
    # site.
    private class FenceRenderer < Markd::HTMLRenderer
      def code_block_body(node : Markd::Node, language : String?)
        # Already chomped by `chomp_code_blocks` below, before this ever
        # runs.
        literal(CodeHighlighter.highlight(node.text, language))
      end
    end

    # Renders a shard's README as safe HTML. `host`, `owner` and `repo` are
    # the shard's identity, used only to resolve a repository-relative image
    # or link; `ref` is the git ref those resolved URLs are built against.
    def self.markdown(source : String?, host : String?, owner : String?, repo : String?, ref : String) : String
      return "" unless source && !source.empty?

      transformed, tables = extract_tables(source)

      options = Markd::Options.new(safe: true)
      document = Markd::Parser.parse(transformed, options)

      resolve_urls(document, host, owner, repo, ref)
      chomp_code_blocks(document)

      html = FenceRenderer.new(options).render(document)
      tables.empty? ? html : splice_tables(html, tables, options, host, owner, repo, ref)
    end

    # Markd keeps the newline before a fence's closing backticks as part of
    # the block's own text, so rendering it unchanged leaves a blank line
    # inside every <pre>. Safe to mutate in place while walking: unlike
    # unlinking or splicing a link or image, replacing a node's own text
    # touches no `next`/`prev`/`parent` pointer, so it cannot corrupt a walk
    # in progress the way the URL resolution pass below can.
    private def self.chomp_code_blocks(node : Markd::Node)
      child = node.first_child?
      while child
        child.text = child.text.chomp if child.type.code_block?
        chomp_code_blocks(child)
        child = child.next?
      end
    end

    # ---- repository-relative URL resolution ---------------------------------

    # A README's images and links are collected before any of them are
    # touched. `Node::Walker`, which the renderer above also uses, precomputes
    # its next node from the current one's own `next`/`parent` pointers, so
    # unlinking or splicing a node while that kind of walk is live corrupts
    # the walk and can skip the rest of the document. Nothing here is
    # mutated until this read-only pass has finished.
    private def self.resolve_urls(document : Markd::Node, host : String?, owner : String?, repo : String?, ref : String)
      targets = [] of Markd::Node
      collect_targets(document, targets)

      targets.each { |node| resolve_node(node, host, owner, repo, ref) }
    end

    private def self.collect_targets(node : Markd::Node, targets : Array(Markd::Node))
      child = node.first_child?
      while child
        targets << child if child.type.link? || child.type.image?
        collect_targets(child, targets)
        child = child.next?
      end
    end

    private def self.resolve_node(node : Markd::Node, host : String?, owner : String?, repo : String?, ref : String)
      destination = node.data["destination"]?.as?(String)
      return unless destination

      image = node.type.image?
      resolved = resolve_url(destination, host, owner, repo, ref, image)

      if resolved
        node.data["destination"] = resolved
      elsif image
        # No URL we could build for this host would resolve, and an <img> with
        # a src that 404s on our own origin is worse than no image at all.
        node.unlink
      else
        # A link we cannot build a working href for still has text worth
        # keeping; only the wrapper that would have pointed nowhere goes.
        unwrap(node)
      end
    end

    # Splices a node's children into its parent in its own place, then
    # removes the now-empty node. Used to turn an unresolvable link into
    # plain text without losing the words inside it.
    private def self.unwrap(node : Markd::Node)
      anchor = node
      child = node.first_child?
      while child
        following = child.next?
        anchor.insert_after(child)
        anchor = child
        child = following
      end
      node.unlink
    end

    # A URL with a scheme, a protocol-relative URL, an in-page anchor, or an
    # empty destination is left exactly as markd parsed it: none of these
    # name a path in the shard's own tree, so there is nothing here to
    # resolve, and rewriting one would only risk breaking a URL that already
    # worked. It still passes through markd's own safe-mode scheme check
    # afterwards, the same as a URL this module did resolve.
    SCHEME = /\A[a-zA-Z][a-zA-Z0-9+.\-]*:/

    private def self.untouchable?(url : String) : Bool
      url.empty? || url.starts_with?('#') || url.starts_with?("//") || !url.match(SCHEME).nil?
    end

    # A leading `./` or `/` both mean "from the repository root": the README
    # itself has no directory of its own to be relative to, it lives at the
    # root, so a root-relative path and a plain relative one resolve the
    # same way.
    private def self.normalize_repo_path(path : String) : String
      path.lchop("./").lchop('/')
    end

    # The absolute URL a repository-relative destination resolves to, or nil
    # when this module does not know how to build one that would not 404 on
    # its own origin. `image` picks the raw-content template over the
    # human-facing one; the two differ per host and neither can stand in for
    # the other.
    private def self.resolve_url(destination : String, host : String?, owner : String?, repo : String?, ref : String, image : Bool) : String?
      return destination if untouchable?(destination)
      return nil unless host && owner && repo

      path = normalize_repo_path(destination)

      case host
      when "github.com"
        image ? "https://raw.githubusercontent.com/#{owner}/#{repo}/#{ref}/#{path}" : "https://github.com/#{owner}/#{repo}/blob/#{ref}/#{path}"
      when "gitlab.com"
        image ? "https://gitlab.com/#{owner}/#{repo}/-/raw/#{ref}/#{path}" : "https://gitlab.com/#{owner}/#{repo}/-/blob/#{ref}/#{path}"
      when "codeberg.org"
        image ? "https://codeberg.org/#{owner}/#{repo}/raw/#{ref}/#{path}" : "https://codeberg.org/#{owner}/#{repo}/src/#{ref}/#{path}"
      else
        # A host without a raw/blob URL scheme we know how to build. Guessing
        # would produce a link that is wrong rather than a link that is
        # merely unresolved, and wrong is worse on a security-sensitive page.
        nil
      end
    end

    # ---- GFM tables -----------------------------------------------------

    # markd 0.5.0 has no table rule at all: `table` appears in
    # lib/markd/src/markd/rule.cr only inside the raw HTML block regex, and
    # safe mode replaces a hand written `<table>` with an omission comment,
    # so a README table would otherwise reach the page as its delimiter row
    # and pipes, read literally, in a paragraph. This scans the raw source
    # for a GFM table before markd ever sees it, replaces each one with an
    # unforgeable placeholder line, renders the rest of the document exactly
    # as it does today, and splices the table's own HTML into the rendered
    # placeholder afterward.

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
      "crystaltable" + Random::Secure.hex(16)
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
    # What this does not attempt: a table cannot interrupt a fenced code
    # block (tracked below, so a README documenting this very syntax inside
    # one reaches the page as the text it is), and a line that would start a
    # new block-level construct with no blank line before it, a blockquote
    # immediately after a table's last row with nothing separating them, is
    # read as one more ragged body row rather than breaking the table the
    # way GFM itself would. Real Markdown puts a blank line there anyway. A
    # table nested inside a blockquote or a list is not attempted at all,
    # the same boundary `CodeHighlighter` draws around the languages it
    # knows: this covers what a shard's README actually does with a table,
    # not the whole of GFM's own block dispatch machinery.
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

        # A header row without a pipe at all is not a table candidate, even
        # though `split_row` would happily hand back its one cell: `Foo`
        # over `---` is a setext heading, not a one-column table, and a
        # bare `---` on its own is a thematic break. Both are exactly as
        # common in a README as an actual table, and both are indistinguishable
        # from a delimiter row by shape alone. Requiring a real pipe in the
        # header is what leaves them to markd's own, correct, handling.
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
    # one per member of `TableAlign`, ever reach the page.
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
    # structure at all. Its links and images are resolved against the
    # repository exactly like any other README link, so a table of badges
    # works the same as the same badges written as plain prose.
    private def self.render_cell(text : String, options : Markd::Options,
                                 host : String?, owner : String?, repo : String?, ref : String) : String
      return "" if text.empty?

      node = Markd::Node.new(Markd::Node::Type::Paragraph)
      node.text = text
      Markd::Parser::Inline.new(options).parse(node)
      resolve_urls(node, host, owner, repo, ref)

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
    # one, GFM's own rule for that too.
    private def self.table_html(table : TableBlock, options : Markd::Options,
                                host : String?, owner : String?, repo : String?, ref : String) : String
      String.build do |io|
        io << "<table><thead><tr>"
        table.header.each_with_index do |cell, index|
          io << "<th" << align_attr(table.alignments[index]) << '>'
          io << render_cell(cell, options, host, owner, repo, ref)
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
              io << render_cell(content, options, host, owner, repo, ref) unless content.empty?
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
    # each is exact, never a prefix of another table's own token.
    private def self.splice_tables(html : String, tables : Hash(String, TableBlock), options : Markd::Options,
                                   host : String?, owner : String?, repo : String?, ref : String) : String
      tables.reduce(html) do |result, (placeholder, table)|
        result.sub("<p>#{placeholder}</p>", table_html(table, options, host, owner, repo, ref))
      end
    end
  end
end
