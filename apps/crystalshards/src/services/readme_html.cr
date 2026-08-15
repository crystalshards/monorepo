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

      options = Markd::Options.new(safe: true)
      document = Markd::Parser.parse(source, options)

      resolve_urls(document, host, owner, repo, ref)
      chomp_code_blocks(document)

      FenceRenderer.new(options).render(document)
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
  end
end
