require "../spec_helper"

# A README was written by whoever published the shard, and Markdown permits
# raw HTML, so it is untrusted input. These specs pin the boundary this
# module leans on markd's own safe mode for: documentation markup survives,
# anything that can execute does not, and the URL resolution this module adds
# on top never emits a link this origin cannot vouch for.
describe CrystalShards::ReadmeHtml do
  describe "rendering Markdown" do
    it "renders headings and lists as elements rather than literal text" do
      html = CrystalShards::ReadmeHtml.markdown(
        "# Kemal\n\n- fast\n- simple\n", "github.com", "kemalcr", "kemal", "master"
      )

      html.should contain("<h1>Kemal</h1>")
      html.should contain("<ul>")
      html.should contain("<li>fast</li>")
      html.should contain("<li>simple</li>")
      html.should_not contain("# Kemal")
      html.should_not contain("- fast")
    end

    it "renders a fenced block as pre > code" do
      html = CrystalShards::ReadmeHtml.markdown(
        "```\nplain text\n```", "github.com", "kemalcr", "kemal", "master"
      )

      html.should match(/<pre><code>plain text<\/code><\/pre>/)
    end

    it "returns empty for no README" do
      CrystalShards::ReadmeHtml.markdown(nil, "github.com", "a", "b", "master").should eq("")
    end
  end

  describe "highlighting code" do
    it "highlights a Crystal fence" do
      html = CrystalShards::ReadmeHtml.markdown(
        %(```crystal\ndef greet\n  "hi" # wave\nend\n```),
        "github.com", "kemalcr", "kemal", "master"
      )

      html.should contain(%(<code class="language-crystal">))
      html.should contain(%(<span class="k">def</span>))
      html.should contain(%(<span class="s">&quot;hi&quot;</span>))
      html.should contain(%(<span class="c"># wave</span>))
    end

    it "highlights a YAML fence" do
      html = CrystalShards::ReadmeHtml.markdown(
        "```yaml\ndependencies:\n  kemal:\n    github: kemalcr/kemal\n```",
        "github.com", "kemalcr", "kemal", "master"
      )

      html.should contain(%(<span class="m">dependencies:</span>))
      html.should contain(%(<span class="m">github:</span>))
      html.should contain(%(<span class="s">kemalcr/kemal</span>))
    end

    it "highlights a shell fence: the command, its flags, and a comment" do
      html = CrystalShards::ReadmeHtml.markdown(
        "```bash\n# install\ncurl -fsSL https://example.com | sh\n```",
        "github.com", "kemalcr", "kemal", "master"
      )

      html.should contain(%(<span class="c"># install</span>))
      html.should contain(%(<span class="m">curl</span>))
      html.should contain(%(<span class="k">-fsSL</span>))
      html.should contain(%(<span class="m">sh</span>))
    end

    it "colours only the prompted line in a shell session, leaving output alone" do
      html = CrystalShards::ReadmeHtml.markdown(
        "```console\n$ shards install\nResolving dependencies\n```",
        "github.com", "kemalcr", "kemal", "master"
      )

      html.should contain(%(<span class="o">$</span>))
      html.should contain(%(<span class="m">shards</span>))
      html.should contain("Resolving dependencies")
    end

    it "highlights a JSON fence's keys, values, numbers and literals" do
      html = CrystalShards::ReadmeHtml.markdown(
        %(```json\n{"name": "kemal", "stable": true, "port": 3000}\n```),
        "github.com", "kemalcr", "kemal", "master"
      )

      html.should contain(%(<span class="m">&quot;name&quot;</span>))
      html.should contain(%(<span class="s">&quot;kemal&quot;</span>))
      html.should contain(%(<span class="k">true</span>))
      html.should contain(%(<span class="n">3000</span>))
    end

    it "names another language's fence without colouring it" do
      html = CrystalShards::ReadmeHtml.markdown(
        %(```toml\nname = "kemal"\n```), "github.com", "kemalcr", "kemal", "master"
      )

      html.should contain(%(<code class="language-toml">))
      html.should_not contain("<span")
    end

    it "renders an unlabelled fence as plain text" do
      html = CrystalShards::ReadmeHtml.markdown(
        "```\nplain\n```", "github.com", "kemalcr", "kemal", "master"
      )

      html.should_not contain("<span")
      html.should contain("plain")
    end
  end

  describe "safe mode" do
    it "never lets a script tag reach the page" do
      html = CrystalShards::ReadmeHtml.markdown(
        "Intro\n\n<script>alert('readme')</script>\n", "github.com", "a", "b", "master"
      )

      html.should_not contain("<script")
      html.should_not contain("alert(&#39;readme&#39;)")
      html.should_not contain("alert('readme')")
    end

    it "never lets inline raw HTML reach the page either" do
      html = CrystalShards::ReadmeHtml.markdown(
        %(Click <img src="x" onerror="alert(1)"> here), "github.com", "a", "b", "master"
      )

      html.should_not contain("onerror")
      html.should contain("Click")
      html.should contain("here")
    end

    it "refuses a javascript: link" do
      html = CrystalShards::ReadmeHtml.markdown(
        "[click me](javascript:alert(1))", "github.com", "a", "b", "master"
      )

      html.should_not contain("javascript:")
      html.should contain("click me")
    end

    it "keeps a genuine https link" do
      html = CrystalShards::ReadmeHtml.markdown(
        "[docs](https://crystal-lang.org)", "github.com", "a", "b", "master"
      )

      html.should contain(%(href="https://crystal-lang.org"))
    end
  end

  describe "resolving a repository-relative image" do
    it "resolves to the raw content URL on github.com" do
      html = CrystalShards::ReadmeHtml.markdown(
        "![Logo](docs/logo.png)", "github.com", "kemalcr", "kemal", "v1.6.0"
      )

      html.should contain(%(src="https://raw.githubusercontent.com/kemalcr/kemal/v1.6.0/docs/logo.png"))
    end

    it "resolves to the raw content URL on gitlab.com" do
      html = CrystalShards::ReadmeHtml.markdown(
        "![Logo](logo.png)", "gitlab.com", "acme", "widget", "main"
      )

      html.should contain(%(src="https://gitlab.com/acme/widget/-/raw/main/logo.png"))
    end

    it "resolves to the raw content URL on codeberg.org" do
      html = CrystalShards::ReadmeHtml.markdown(
        "![Logo](logo.png)", "codeberg.org", "acme", "widget", "main"
      )

      html.should contain(%(src="https://codeberg.org/acme/widget/raw/main/logo.png"))
    end

    it "resolves a root-relative path the same way as a plain relative one" do
      rooted = CrystalShards::ReadmeHtml.markdown(
        "![Logo](/assets/logo.png)", "github.com", "kemalcr", "kemal", "master"
      )
      plain = CrystalShards::ReadmeHtml.markdown(
        "![Logo](assets/logo.png)", "github.com", "kemalcr", "kemal", "master"
      )

      expected = %(src="https://raw.githubusercontent.com/kemalcr/kemal/master/assets/logo.png")
      rooted.should contain(expected)
      plain.should contain(expected)
    end

    it "drops the image entirely on a host with no known raw URL" do
      html = CrystalShards::ReadmeHtml.markdown(
        "before ![Logo](logo.png) after", "sourcehut.org", "acme", "widget", "master"
      )

      html.should_not contain("<img")
      html.should_not contain("logo.png")
      html.should contain("before")
      html.should contain("after")
    end

    it "drops the image when the shard has no identity to resolve against" do
      html = CrystalShards::ReadmeHtml.markdown(
        "![Logo](logo.png)", nil, nil, nil, "master"
      )

      html.should_not contain("<img")
    end

    it "never rewrites an absolute image URL" do
      html = CrystalShards::ReadmeHtml.markdown(
        "![Badge](https://img.shields.io/badge/CI-passing-green)",
        "github.com", "kemalcr", "kemal", "master"
      )

      html.should contain(%(src="https://img.shields.io/badge/CI-passing-green"))
    end

    it "never rewrites a protocol-relative image URL" do
      html = CrystalShards::ReadmeHtml.markdown(
        "![Badge](//img.shields.io/badge/CI-passing-green)",
        "github.com", "kemalcr", "kemal", "master"
      )

      html.should contain(%(src="//img.shields.io/badge/CI-passing-green"))
    end
  end

  describe "resolving a repository-relative link" do
    it "resolves to the human-facing blob URL on github.com" do
      html = CrystalShards::ReadmeHtml.markdown(
        "[Changelog](CHANGELOG.md)", "github.com", "kemalcr", "kemal", "v1.6.0"
      )

      html.should contain(%(href="https://github.com/kemalcr/kemal/blob/v1.6.0/CHANGELOG.md"))
    end

    it "resolves to the human-facing blob URL on gitlab.com" do
      html = CrystalShards::ReadmeHtml.markdown(
        "[Changelog](CHANGELOG.md)", "gitlab.com", "acme", "widget", "main"
      )

      html.should contain(%(href="https://gitlab.com/acme/widget/-/blob/main/CHANGELOG.md"))
    end

    it "resolves to the human-facing source URL on codeberg.org" do
      html = CrystalShards::ReadmeHtml.markdown(
        "[Changelog](CHANGELOG.md)", "codeberg.org", "acme", "widget", "main"
      )

      html.should contain(%(href="https://codeberg.org/acme/widget/src/main/CHANGELOG.md"))
    end

    it "unwraps a link to plain text on a host with no known blob URL, keeping its words" do
      html = CrystalShards::ReadmeHtml.markdown(
        "See the [Changelog](CHANGELOG.md) for history.",
        "sourcehut.org", "acme", "widget", "master"
      )

      html.should_not contain("<a ")
      html.should_not contain("CHANGELOG.md")
      html.should contain("Changelog")
      html.should contain("for history")
    end

    it "leaves an in-page anchor link alone" do
      html = CrystalShards::ReadmeHtml.markdown(
        "[Usage](#usage)", "github.com", "kemalcr", "kemal", "master"
      )

      html.should contain(%(href="#usage"))
    end
  end

  describe "badges: an image nested inside a link" do
    it "resolves both the image and the link independently" do
      html = CrystalShards::ReadmeHtml.markdown(
        "[![Build](badge.svg)](actions.html)", "github.com", "kemalcr", "kemal", "master"
      )

      html.should contain(%(src="https://raw.githubusercontent.com/kemalcr/kemal/master/badge.svg"))
      html.should contain(%(href="https://github.com/kemalcr/kemal/blob/master/actions.html"))
    end
  end

  # markd 0.5.0 has no table rule of its own, so these pin the boundary this
  # module adds on top of it: a GFM table renders as a real table, a cell
  # keeps its own inline markdown, and the placeholder that carries a
  # table's HTML through markd cannot be forged from the README's own text.
  describe "rendering GFM tables" do
    it "renders a plain table as table, thead and tbody" do
      html = CrystalShards::ReadmeHtml.markdown(
        "| Player | Preferences |\n| ------ | ------ |\n| Jason | dark mode |\n",
        "github.com", "kemalcr", "kemal", "master"
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
      html = CrystalShards::ReadmeHtml.markdown(
        "| Left | Center | Right |\n| :--- | :---: | ---: |\n| a | b | c |\n",
        "github.com", "kemalcr", "kemal", "master"
      )

      html.should contain(%(<th align="left">Left</th>))
      html.should contain(%(<th align="center">Center</th>))
      html.should contain(%(<th align="right">Right</th>))
      html.should contain(%(<td align="left">a</td>))
      html.should contain(%(<td align="center">b</td>))
      html.should contain(%(<td align="right">c</td>))
    end

    it "renders a cell's own inline markdown: a code span and a link" do
      html = CrystalShards::ReadmeHtml.markdown(
        "| Cell |\n| --- |\n| `code` and [docs](https://crystal-lang.org) |\n",
        "github.com", "kemalcr", "kemal", "master"
      )

      html.should contain("<code>code</code>")
      html.should contain(%(<a href="https://crystal-lang.org">docs</a>))
    end

    it "unescapes a pipe escaped inside a cell, including inside a code span" do
      html = CrystalShards::ReadmeHtml.markdown(
        "| Col |\n| --- |\n| a \\| b |\n| `x\\|y` |\n",
        "github.com", "kemalcr", "kemal", "master"
      )

      html.should contain("<td>a | b</td>")
      html.should contain("<td><code>x|y</code></td>")
      html.should_not contain("\\|")
    end

    it "pads a row with too few cells and ignores the excess in one with too many" do
      html = CrystalShards::ReadmeHtml.markdown(
        "| A | B |\n| - | - |\n| short |\n| too | many | cells |\n",
        "github.com", "kemalcr", "kemal", "master"
      )

      html.should contain("<td>short</td><td></td>")
      html.should contain("<td>too</td><td>many</td></tr>")
      html.should_not contain("cells</td>")
    end

    it "renders a table at the very start of a document" do
      html = CrystalShards::ReadmeHtml.markdown(
        "| a | b |\n| - | - |\n| 1 | 2 |\n\nAfter the table.\n",
        "github.com", "kemalcr", "kemal", "master"
      )

      html.should contain("<table>")
      html.should contain("After the table.")
    end

    it "renders a table at the very end of a document" do
      html = CrystalShards::ReadmeHtml.markdown(
        "Before the table.\n\n| a | b |\n| - | - |\n| 1 | 2 |\n",
        "github.com", "kemalcr", "kemal", "master"
      )

      html.should contain("Before the table.")
      html.should contain("<table>")
    end

    it "renders two tables in one document" do
      html = CrystalShards::ReadmeHtml.markdown(
        "| a | b |\n| - | - |\n| 1 | 2 |\n\nBetween.\n\n| c | d |\n| - | - |\n| 3 | 4 |\n",
        "github.com", "kemalcr", "kemal", "master"
      )

      html.scan(/<table>/).size.should eq(2)
      html.should contain("<td>1</td>")
      html.should contain("<td>3</td>")
      html.should contain("Between.")
    end

    it "leaves a line of pipes with no delimiter row as an ordinary paragraph" do
      html = CrystalShards::ReadmeHtml.markdown(
        "| abc | def |\nsome text\n", "github.com", "kemalcr", "kemal", "master"
      )

      html.should_not contain("<table>")
      html.should contain("<p>")
      html.should contain("abc")
      html.should contain("def")
    end

    it "does not read a setext heading's own underline as a one-column delimiter row" do
      html = CrystalShards::ReadmeHtml.markdown(
        "Foo\n---\n\nbody\n", "github.com", "kemalcr", "kemal", "master"
      )

      html.should_not contain("<table>")
      html.should contain("<h2>Foo</h2>")
    end

    it "leaves a table written inside a fenced code block as the text it is" do
      html = CrystalShards::ReadmeHtml.markdown(
        "```\n| a | b |\n| - | - |\n| 1 | 2 |\n```\n",
        "github.com", "kemalcr", "kemal", "master"
      )

      html.should_not contain("<table>")
      html.should contain("| a | b |")
    end

    it "omits tbody entirely when a table has no body rows" do
      html = CrystalShards::ReadmeHtml.markdown(
        "| a | b |\n| - | - |\n", "github.com", "kemalcr", "kemal", "master"
      )

      html.should contain("<table>")
      html.should_not contain("<tbody>")
    end

    it "resolves a repository-relative image inside a cell the same way it does in prose" do
      html = CrystalShards::ReadmeHtml.markdown(
        "| Badge |\n| --- |\n| ![Build](badge.svg) |\n",
        "github.com", "kemalcr", "kemal", "v1.6.0"
      )

      html.should contain(%(src="https://raw.githubusercontent.com/kemalcr/kemal/v1.6.0/badge.svg"))
    end

    it "never lets a script tag inside a cell reach the page" do
      html = CrystalShards::ReadmeHtml.markdown(
        "| Col |\n| --- |\n| <script>alert(1)</script> |\n",
        "github.com", "a", "b", "master"
      )

      html.should_not contain("<script")
      html.should_not contain("</script>")
    end

    it "refuses a javascript: link inside a cell" do
      html = CrystalShards::ReadmeHtml.markdown(
        "| Col |\n| --- |\n| [xss](javascript:alert(1)) |\n",
        "github.com", "a", "b", "master"
      )

      html.should_not contain("javascript:")
      html.should contain("xss")
    end

    it "cannot be tricked into injecting markup by guessing at the placeholder" do
      guess = "crystaltable" + "0" * 32
      html = CrystalShards::ReadmeHtml.markdown(
        "Here is some text: #{guess}\n", "github.com", "kemalcr", "kemal", "master"
      )

      html.should_not contain("<table>")
      html.should contain(guess)
    end
  end
end
