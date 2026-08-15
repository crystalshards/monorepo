require "../spec_helper"

# A hash link is only fixed when something on the page answers to it, so the
# specs below check the pair rather than either half on its own.
private def fragment_targets(html : String) : Array(String)
  html.scan(/href="#([^"]*)"/).map(&.[1])
end

private def element_ids(html : String) : Array(String)
  html.scan(/id="([^"]*)"/).map(&.[1])
end

# What a reader actually sees in a code block: the markup dropped and the
# entities decoded once, the way a browser decodes them. Asserting on the
# encoded form would pass just as happily on text encoded twice, which is
# the bug these specs exist to hold shut.
private def code_block_text(html : String) : String
  match = html.match(/<pre><code[^>]*>(.*?)<\/code><\/pre>/m)
  raise "no code block in: #{html}" unless match

  HTML.unescape(match[1].gsub(/<[^>]+>/, ""))
end

# Everything in a docs.json was written by whoever published the shard, and we
# display it richly. These specs pin the boundary: documentation markup
# survives, anything that can execute does not.
describe CrystalDocs::DocHtml do
  describe "sanitising compiler-rendered doc comments" do
    it "keeps the markup documentation actually uses" do
      html = CrystalDocs::DocHtml.sanitize(
        "<p>Stores <code>config</code> options.</p><ul><li><strong>one</strong></li></ul>"
      )

      html.should contain("<p>")
      html.should contain("<code>")
      html.should contain("<strong>")
      html.should contain("Stores")
    end

    it "drops a script tag and the code inside it" do
      html = CrystalDocs::DocHtml.sanitize("<p>hi</p><script>alert('xss')</script>")

      html.should_not contain("<script")
      html.should_not contain("</script>")
      # The code goes too. Escaping it would be safe but would leave someone
      # else's payload sitting in our page as prose.
      html.should_not contain("alert")
      html.should contain("<p>hi</p>")
    end

    it "drops event handler attributes" do
      html = CrystalDocs::DocHtml.sanitize(%(<p onclick="steal()">text</p>))

      html.should_not contain("onclick")
      html.should contain("text")
    end

    it "refuses a javascript: link but keeps a real one" do
      hostile = CrystalDocs::DocHtml.sanitize(%(<a href="javascript:alert(1)">click</a>))
      genuine = CrystalDocs::DocHtml.sanitize(%(<a href="https://crystal-lang.org">docs</a>))

      hostile.should_not contain("javascript:")
      genuine.should contain(%(href="https://crystal-lang.org"))
    end

    it "does not let an unclosed attribute smuggle a tag" do
      html = CrystalDocs::DocHtml.sanitize(%(<img src="x" onerror="alert(1)">))

      html.should_not contain("onerror")
    end

    it "keeps surrounding prose when a dangerous tag is never closed" do
      html = CrystalDocs::DocHtml.sanitize("use <script> carefully")

      html.should_not contain("<script")
      html.should contain("use")
      html.should contain("carefully")
    end
  end

  describe "rendering a README" do
    it "renders Markdown to HTML" do
      html = CrystalDocs::DocHtml.markdown("# Title\n\nSome **bold** text.")

      html.should contain("Title")
      html.should contain("<strong>bold</strong>")
    end

    it "strips inline HTML that Markdown happily passes through" do
      # Markdown permits raw HTML, so a README is an injection vector unless
      # the rendered output is sanitised too.
      html = CrystalDocs::DocHtml.markdown("Intro\n\n<script>alert('readme')</script>\n")

      html.should_not contain("<script")
      html.should_not contain("alert('readme')</script>")
    end

    it "strips an onerror image from a README" do
      html = CrystalDocs::DocHtml.markdown(%q{<img src="x" onerror="alert(1)">})

      html.should_not contain("onerror")
    end

    it "returns empty for no README" do
      CrystalDocs::DocHtml.markdown(nil).should eq("")
    end

    # Markd encodes the text it emits, and this module encoded it again, so
    # every quote in every code block on the site reached the reader as a
    # literal `&quot;`. These pin the encoding at exactly once.
    it "renders a quote in a code fence as a quote" do
      html = CrystalDocs::DocHtml.markdown(%(```\nputs "hello"\n```))

      code_block_text(html).should eq(%(puts "hello"))
      html.should_not contain("&amp;quot;")
    end

    it "renders an ampersand in prose as an ampersand" do
      html = CrystalDocs::DocHtml.markdown("Tom & Jerry")

      html.should contain("Tom &amp; Jerry")
      html.should_not contain("&amp;amp;")
    end

    it "keeps the separators in a link's query string" do
      html = CrystalDocs::DocHtml.markdown("[x](https://example.com/?a=1&b=2)")

      html.should contain(%(href="https://example.com/?a=1&amp;b=2"))
    end

    # Decoding the text before re-encoding it is what fixed the quotes, so
    # these two hold the other half: nothing decoded can arrive as markup.
    it "leaves a script tag inside a code fence as text" do
      html = CrystalDocs::DocHtml.markdown("```\n<script>alert(1)</script>\n```")

      html.should_not contain("<script")
      code_block_text(html).should eq("<script>alert(1)</script>")
    end

    it "does not decode an escaped script tag back into one" do
      html = CrystalDocs::DocHtml.sanitize("<p>&lt;script&gt;alert(1)&lt;/script&gt;</p>")

      html.should_not contain("<script")
      html.should contain("&lt;script&gt;alert(1)&lt;/script&gt;")
    end
  end

  describe "highlighting code" do
    it "highlights a Crystal fence" do
      html = CrystalDocs::DocHtml.markdown(%(```crystal\ndef greet\n  "hi" # wave\nend\n```))

      html.should contain(%(<code class="language-crystal">))
      html.should contain(%(<span class="k">def</span>))
      html.should contain(%(<span class="s">&quot;hi&quot;</span>))
      html.should contain(%(<span class="c"># wave</span>))
      # Highlighting must not disturb what the block says.
      code_block_text(html).should eq(%(def greet\n  "hi" # wave\nend))
    end

    it "names another language's fence without colouring it" do
      html = CrystalDocs::DocHtml.markdown(%(```toml\nname = "kemal"\n```))

      html.should contain(%(<code class="language-toml">))
      html.should_not contain("<span")
    end

    it "renders a Crystal fence the lexer rejects as plain text" do
      # A README's install block is labelled crystal often enough, and a shell
      # prompt is not Crystal. The highlighter falls back rather than raising.
      html = CrystalDocs::DocHtml.markdown("```crystal\n$ shards install\n```")

      html.should_not contain("<span")
      code_block_text(html).should eq("$ shards install")
    end

    it "highlights a YAML fence" do
      html = CrystalDocs::DocHtml.markdown(
        "```yaml\ndependencies:\n  kemal:\n    github: kemalcr/kemal\n```"
      )

      html.should contain(%(<code class="language-yaml">))
      html.should contain(%(<span class="m">dependencies:</span>))
      html.should contain(%(<span class="m">github:</span>))
      html.should contain(%(<span class="s">kemalcr/kemal</span>))
    end

    it "highlights a shell fence: the command, its flags, and a comment" do
      html = CrystalDocs::DocHtml.markdown(
        "```bash\n# install\ncurl -fsSL https://example.com | sh\n```"
      )

      html.should contain(%(<span class="c"># install</span>))
      html.should contain(%(<span class="m">curl</span>))
      html.should contain(%(<span class="k">-fsSL</span>))
      html.should contain(%(<span class="m">sh</span>))
    end

    it "colours only the prompted line in a shell session, leaving output alone" do
      html = CrystalDocs::DocHtml.markdown(
        "```console\n$ shards install\nResolving dependencies\n```"
      )

      html.should contain(%(<span class="o">$</span>))
      html.should contain(%(<span class="m">shards</span>))
      html.should contain("Resolving dependencies")
    end

    it "highlights a JSON fence's keys, values, numbers and literals" do
      html = CrystalDocs::DocHtml.markdown(
        %(```json\n{"name": "kemal", "stable": true, "port": 3000}\n```)
      )

      html.should contain(%(<span class="m">&quot;name&quot;</span>))
      html.should contain(%(<span class="s">&quot;kemal&quot;</span>))
      html.should contain(%(<span class="k">true</span>))
      html.should contain(%(<span class="n">3000</span>))
    end

    it "renders an unlabelled fence as plain text" do
      html = CrystalDocs::DocHtml.markdown("```\nplain\n```")

      html.should_not contain("<span")
      code_block_text(html).should eq("plain")
    end

    it "keeps the highlighting the compiler already did" do
      html = CrystalDocs::DocHtml.sanitize(
        %(<pre><code class="language-crystal"><span class="k">def</span>) +
        %(<span class="t">String</span></code></pre>)
      )

      html.should contain(%(<span class="k">def</span>))
      html.should contain(%(<span class="t">String</span>))
    end

    it "drops a class the highlighter never emits" do
      html = CrystalDocs::DocHtml.sanitize(%(<p><span class="site-header">x</span></p>))

      html.should contain("<span>x</span>")
    end

    it "drops a class on a code element that does not name a language" do
      html = CrystalDocs::DocHtml.sanitize(%(<code class="prettyprint">y</code>))

      html.should contain("<code>y</code>")
    end

    it "rebuilds a language class rather than trusting the fence label" do
      html = CrystalDocs::DocHtml.sanitize(
        %(<code class="language-'><img src=x onerror=alert(1)>">y</code>)
      )

      # The payload's characters survive only as letters inside the slug: the
      # quote, the angle brackets and the `=` are all gone, so there is no
      # tag and no attribute, just a language nobody will ever write.
      html.should contain(%(<code class="language-imgsrcxonerroralert1">y</code>))
      html.should_not contain("<img")
      html.should_not contain("onerror=")
    end
  end

  describe "anchoring a README to its own headings" do
    it "gives a heading the id its own hash link points at" do
      html = CrystalDocs::DocHtml.markdown("[Installation](#installation)\n\n## Installation\n")

      targets = fragment_targets(html)
      targets.should eq(["installation"])
      element_ids(html).should contain(targets.first)
    end

    it "slugs the way GitHub does, because that is what authors linked against" do
      html = CrystalDocs::DocHtml.markdown("## Usage & Setup\n\n### What's new?\n\n#### API Reference (v2)\n")

      ids = element_ids(html)
      # Punctuation is dropped without leaving a separator behind and spaces
      # become hyphens, so an "&" between two spaces yields a double hyphen.
      # GitHub does the same, and a README written for GitHub links to it.
      ids.should eq(["usage--setup", "whats-new", "api-reference-v2"])
    end

    it "slugs a heading on its words rather than on its markup" do
      html = CrystalDocs::DocHtml.markdown("## The `parse` method\n")

      element_ids(html).should eq(["the-parse-method"])
    end

    it "gives repeated headings distinct ids" do
      html = CrystalDocs::DocHtml.markdown("## Usage\n\n## Usage\n\n## Usage\n")

      ids = element_ids(html)
      ids.should eq(["usage", "usage-1", "usage-2"])
      ids.uniq.size.should eq(ids.size)
    end

    it "keeps an id an author wrote by hand" do
      html = CrystalDocs::DocHtml.sanitize(%(<h2 id="install">Install</h2>))

      html.should contain(%(<h2 id="install">))
    end

    it "leaves a heading with no sluggable text without an id" do
      html = CrystalDocs::DocHtml.sanitize("<h2>***</h2>")

      html.should contain("<h2>")
      element_ids(html).should be_empty
    end

    it "keeps a same-document hash link on an anchor" do
      html = CrystalDocs::DocHtml.sanitize(%(<a href="#section">jump</a>))

      html.should contain(%(href="#section"))
    end

    it "strips an id from anything that is not a heading" do
      html = CrystalDocs::DocHtml.sanitize(
        %(<p id="p">para</p><div id="d">block</div>) +
        %(<a id="a" href="#x">link</a><span id="s">s</span>)
      )

      element_ids(html).should be_empty
      # The anchor keeps the attributes it is actually allowed.
      html.should contain(%(href="#x"))
    end

    it "cannot be broken out of by a quote in the heading text" do
      html = CrystalDocs::DocHtml.sanitize(%(<h2>x" onload="alert(1)</h2>))

      # The quote cannot survive the character constraint, so the attribute
      # closes where we closed it and no second attribute is created. Only
      # the space becomes a hyphen: the `="` is dropped without a separator,
      # which is why onload and alert run together.
      html.should contain(%(<h2 id="x-onloadalert1">))
      html.should_not contain(%(onload="))
      element_ids(html).each { |id| id.should_not contain('"') }
    end

    it "cannot be broken out of by markup smuggled into a declared id" do
      html = CrystalDocs::DocHtml.sanitize(
        %(<h2 id='x"><img src=x onerror=alert(1)>'>Title</h2>)
      )

      html.should contain(%(<h2 id="ximg-srcx-onerroralert1">))
      html.should_not contain("<img")
      html.should_not contain("onerror=")
      html.should contain("Title")
    end

    it "still refuses a javascript: link and an event handler on a heading" do
      html = CrystalDocs::DocHtml.sanitize(
        %(<h2 id="t" onclick="steal()">t</h2><a href="javascript:alert(1)">go</a>)
      )

      html.should contain(%(<h2 id="t">))
      html.should_not contain("onclick")
      html.should_not contain("javascript:")
    end
  end

  describe "resolving a repository-relative README reference" do
    it "resolves a relative image against a github repository" do
      html = CrystalDocs::DocHtml.sanitize(
        %(<img src="doc/assets/logo.svg" alt="logo">),
        repository: "github.com/crystal-lang/crystal", ref: "1.21.0"
      )
      raw = "https://raw.githubusercontent.com/crystal-lang/crystal/1.21.0/doc/assets/logo.svg"

      html.should contain(%(src="#{raw}"))
    end

    it "resolves a relative link against a github repository" do
      html = CrystalDocs::DocHtml.sanitize(
        %(<a href="CONTRIBUTING.md">contributing</a>),
        repository: "github.com/crystal-lang/crystal", ref: "1.21.0"
      )
      blob = "https://github.com/crystal-lang/crystal/blob/1.21.0/CONTRIBUTING.md"

      html.should contain(%(href="#{blob}"))
    end

    it "fixes the reported case: a README image that 404d against our own origin" do
      html = CrystalDocs::DocHtml.markdown(
        "![Crystal - Born and raised at Manas](doc/assets/crystal-born-and-raised.svg)",
        repository: "github.com/crystal-lang/crystal", ref: "1.21.0"
      )
      raw = "https://raw.githubusercontent.com/crystal-lang/crystal/1.21.0/" \
            "doc/assets/crystal-born-and-raised.svg"

      html.should contain(%(src="#{raw}"))
    end

    it "resolves a relative image and link against a gitlab repository" do
      image = CrystalDocs::DocHtml.sanitize(
        %(<img src="assets/logo.png">),
        repository: "gitlab.com/acme/lib", ref: "2.0.0"
      )
      link = CrystalDocs::DocHtml.sanitize(
        %(<a href="CHANGELOG.md">changelog</a>),
        repository: "gitlab.com/acme/lib", ref: "2.0.0"
      )

      image.should contain(%(src="https://gitlab.com/acme/lib/-/raw/2.0.0/assets/logo.png"))
      link.should contain(%(href="https://gitlab.com/acme/lib/-/blob/2.0.0/CHANGELOG.md"))
    end

    it "resolves a relative image and link against a codeberg repository" do
      image = CrystalDocs::DocHtml.sanitize(
        %(<img src="banner.png">),
        repository: "codeberg.org/acme/lib", ref: "0.5.0"
      )
      link = CrystalDocs::DocHtml.sanitize(
        %(<a href="LICENSE">license</a>),
        repository: "codeberg.org/acme/lib", ref: "0.5.0"
      )

      image.should contain(%(src="https://codeberg.org/acme/lib/raw/0.5.0/banner.png"))
      link.should contain(%(href="https://codeberg.org/acme/lib/src/0.5.0/LICENSE"))
    end

    it "drops an image and unwraps a link when the repository host is unknown" do
      image = CrystalDocs::DocHtml.sanitize(
        %(<img src="assets/logo.png">),
        repository: "bitbucket.org/acme/lib", ref: "1.0.0"
      )
      link = CrystalDocs::DocHtml.sanitize(
        %(<a href="docs/guide.md">guide</a>),
        repository: "bitbucket.org/acme/lib", ref: "1.0.0"
      )

      image.should_not contain("<img")
      link.should_not contain("<a")
      link.should contain("guide")
    end

    it "leaves an absolute URL untouched even with a repository given" do
      html = CrystalDocs::DocHtml.sanitize(
        %(<img src="https://example.com/logo.png">),
        repository: "github.com/crystal-lang/crystal", ref: "1.21.0"
      )

      html.should contain(%(src="https://example.com/logo.png"))
    end

    it "leaves a protocol relative URL untouched" do
      html = CrystalDocs::DocHtml.sanitize(
        %(<img src="//cdn.example.com/logo.png">),
        repository: "github.com/crystal-lang/crystal", ref: "1.21.0"
      )

      html.should contain(%(src="//cdn.example.com/logo.png"))
    end

    it "resolves a root relative path the same way as a plain relative one" do
      root_relative = CrystalDocs::DocHtml.sanitize(
        %(<img src="/doc/assets/logo.png">),
        repository: "github.com/crystal-lang/crystal", ref: "1.21.0"
      )
      plain_relative = CrystalDocs::DocHtml.sanitize(
        %(<img src="doc/assets/logo.png">),
        repository: "github.com/crystal-lang/crystal", ref: "1.21.0"
      )

      root_relative.should eq(plain_relative)
      raw = "https://raw.githubusercontent.com/crystal-lang/crystal/1.21.0/doc/assets/logo.png"
      root_relative.should contain(%(src="#{raw}"))
    end

    it "drops a relative image and keeps an absolute reference in a doc comment" do
      # A doc comment never carries a repository: `sanitize` is called
      # directly, with neither argument, exactly as the compiler's own
      # rendered HTML reaches it today.
      html = CrystalDocs::DocHtml.sanitize(
        %(<img src="doc/assets/logo.png"><a href="https://crystal-lang.org">site</a>)
      )

      html.should_not contain("<img")
      html.should contain(%(href="https://crystal-lang.org"))
    end

    it "unwraps a relative link to plain text in a doc comment" do
      html = CrystalDocs::DocHtml.sanitize(%(<a href="docs/guide.md">guide</a>))

      html.should_not contain("<a")
      html.should contain("guide")
    end

    it "still refuses a javascript: URL after it passes through the rewrite step" do
      html = CrystalDocs::DocHtml.sanitize(
        %(<a href="javascript:alert(1)">click</a>),
        repository: "github.com/crystal-lang/crystal", ref: "1.21.0"
      )

      html.should_not contain("javascript:")
      html.should contain(%(<a rel="nofollow noopener">click</a>))
    end
  end

  # markd 0.5.0 has no table rule of its own, so these pin the boundary this
  # module adds on top of it: a GFM table renders as a real table, a cell
  # keeps its own inline markdown, the table this module builds survives
  # `sanitize` rather than being stripped by it, and the placeholder that
  # carries a table's HTML through markd cannot be forged from the
  # README's own text.
  describe "rendering GFM tables" do
    it "renders a plain table as table, thead and tbody" do
      html = CrystalDocs::DocHtml.markdown(
        "| Player | Preferences |\n| ------ | ------ |\n| Jason | dark mode |\n"
      )

      html.should contain("<table>")
      html.should contain("<thead>")
      html.should contain("<tbody>")
      html.should contain("<th>Player</th>")
      html.should contain("<th>Preferences</th>")
      html.should contain("<td>Jason</td>")
      html.should contain("<td>dark mode</td>")
      html.should_not contain("| Player | Preferences |")
    end

    it "carries alignment from the delimiter row's leading and trailing colons" do
      html = CrystalDocs::DocHtml.markdown(
        "| Left | Center | Right |\n| :--- | :---: | ---: |\n| a | b | c |\n"
      )

      html.should contain(%(<th align="left">Left</th>))
      html.should contain(%(<th align="center">Center</th>))
      html.should contain(%(<th align="right">Right</th>))
      html.should contain(%(<td align="left">a</td>))
      html.should contain(%(<td align="center">b</td>))
      html.should contain(%(<td align="right">c</td>))
    end

    it "renders a cell's own inline markdown: a code span and a link" do
      html = CrystalDocs::DocHtml.markdown(
        "| Cell |\n| --- |\n| `code` and [docs](https://crystal-lang.org) |\n"
      )

      html.should contain("<code>code</code>")
      html.should contain(%(<a href="https://crystal-lang.org" rel="nofollow noopener">docs</a>))
    end

    it "unescapes a pipe escaped inside a cell, including inside a code span" do
      html = CrystalDocs::DocHtml.markdown(
        "| Col |\n| --- |\n| a \\| b |\n| `x\\|y` |\n"
      )

      html.should contain("<td>a | b</td>")
      html.should contain("<td><code>x|y</code></td>")
      html.should_not contain("\\|")
    end

    it "pads a row with too few cells and ignores the excess in one with too many" do
      html = CrystalDocs::DocHtml.markdown(
        "| A | B |\n| - | - |\n| short |\n| too | many | cells |\n"
      )

      html.should contain("<td>short</td><td></td>")
      html.should contain("<td>too</td><td>many</td></tr>")
      html.should_not contain("cells</td>")
    end

    it "renders a table at the very start of a document" do
      html = CrystalDocs::DocHtml.markdown(
        "| a | b |\n| - | - |\n| 1 | 2 |\n\nAfter the table.\n"
      )

      html.should contain("<table>")
      html.should contain("After the table.")
    end

    it "renders a table at the very end of a document" do
      html = CrystalDocs::DocHtml.markdown(
        "Before the table.\n\n| a | b |\n| - | - |\n| 1 | 2 |\n"
      )

      html.should contain("Before the table.")
      html.should contain("<table>")
    end

    it "renders two tables in one document" do
      html = CrystalDocs::DocHtml.markdown(
        "| a | b |\n| - | - |\n| 1 | 2 |\n\nBetween.\n\n| c | d |\n| - | - |\n| 3 | 4 |\n"
      )

      html.scan(/<table>/).size.should eq(2)
      html.should contain("<td>1</td>")
      html.should contain("<td>3</td>")
      html.should contain("Between.")
    end

    it "leaves a line of pipes with no delimiter row as an ordinary paragraph" do
      html = CrystalDocs::DocHtml.markdown("| abc | def |\nsome text\n")

      html.should_not contain("<table>")
      html.should contain("<p>")
      html.should contain("abc")
      html.should contain("def")
    end

    it "does not read a setext heading's own underline as a one-column delimiter row" do
      html = CrystalDocs::DocHtml.markdown("Foo\n---\n\nbody\n")

      html.should_not contain("<table>")
      html.should contain("Foo</h2>")
    end

    it "leaves a table written inside a fenced code block as the text it is" do
      html = CrystalDocs::DocHtml.markdown("```\n| a | b |\n| - | - |\n| 1 | 2 |\n```\n")

      html.should_not contain("<table>")
      html.should contain("| a | b |")
    end

    it "omits tbody entirely when a table has no body rows" do
      html = CrystalDocs::DocHtml.markdown("| a | b |\n| - | - |\n")

      html.should contain("<table>")
      html.should_not contain("<tbody>")
    end

    it "resolves a repository-relative image inside a cell the same way it does in prose" do
      html = CrystalDocs::DocHtml.markdown(
        "| Badge |\n| --- |\n| ![Build](assets/badge.svg) |\n",
        repository: "github.com/crystal-lang/crystal", ref: "1.21.0"
      )

      raw = "https://raw.githubusercontent.com/crystal-lang/crystal/1.21.0/assets/badge.svg"
      html.should contain(%(src="#{raw}"))
    end

    it "never lets a script tag inside a cell reach the page" do
      html = CrystalDocs::DocHtml.markdown("| Col |\n| --- |\n| <script>alert(1)</script> |\n")

      html.should_not contain("<script")
      html.should_not contain("alert(1)")
    end

    it "refuses a javascript: link inside a cell" do
      html = CrystalDocs::DocHtml.markdown("| Col |\n| --- |\n| [xss](javascript:alert(1)) |\n")

      html.should_not contain("javascript:")
      html.should contain("xss")
    end

    it "cannot be tricked into injecting markup by guessing at the placeholder" do
      guess = "crystaldocstable" + "0" * 32
      html = CrystalDocs::DocHtml.markdown("Here is some text: #{guess}\n")

      html.should_not contain("<table>")
      html.should contain(guess)
    end

    # `markdown` always sends its output through `sanitize`, so every test
    # above already proves the table survives that pass. These call
    # `sanitize` directly, the way the rest of this file isolates the
    # allowlist from parsing, to pin the allowlist's own shape: exactly the
    # tags and the three alignment values this module's own table builder
    # uses, nothing a shard author could reach some other way.
    it "keeps a hand written table's tags and its align attribute through the sanitizer" do
      html = CrystalDocs::DocHtml.sanitize(
        %(<table><thead><tr><th align="center">A</th></tr></thead>) +
        %(<tbody><tr><td align="center">1</td></tr></tbody></table>)
      )

      html.should contain("<table>")
      html.should contain("<thead>")
      html.should contain("<tbody>")
      html.should contain(%(<th align="center">A</th>))
      html.should contain(%(<td align="center">1</td>))
    end

    it "rebuilds align from a fixed set rather than trusting the value written" do
      html = CrystalDocs::DocHtml.sanitize(%(<table><tr><td align="justify">x</td></tr></table>))

      html.should_not contain("align=")
      html.should contain("<td>x</td>")
    end
  end
end
