require "../spec_helper"

# `CodeHighlighter` is the module `CrystalDocs::DocHtml` and
# `CrystalShards::ReadmeHtml` both run a fence through. These specs exercise
# it directly, one language at a time, rather than through either renderer:
# what a key, a value, a comment or a fallback becomes is a property of this
# module, not of Markdown or of the sanitiser layered on top of it.
describe CrystalDocs::CodeHighlighter do
  describe "Crystal" do
    it "delegates to the compiler's own highlighter" do
      html = CrystalDocs::CodeHighlighter.highlight(%(def greet\n  "hi" # wave\nend), "crystal")

      html.should contain(%(<span class="k">def</span>))
      html.should contain(%(<span class="m">greet</span>))
      html.should contain(%(<span class="s">&quot;hi&quot;</span>))
      html.should contain(%(<span class="c"># wave</span>))
    end

    it "accepts the short alias" do
      CrystalDocs::CodeHighlighter.highlight("1 + 1", "cr")
        .should contain(%(<span class="n">1</span>))
    end

    it "falls back to plain escaped source when the lexer rejects the block" do
      html = CrystalDocs::CodeHighlighter.highlight("$ shards install", "crystal")

      html.should eq("$ shards install")
      html.should_not contain("<span")
    end
  end

  describe "YAML" do
    it "colours a key up to and including its colon" do
      html = CrystalDocs::CodeHighlighter.highlight("dependencies:", "yaml")

      html.should eq(%(<span class="m">dependencies:</span>))
    end

    it "colours an indented key, keeping its indent plain" do
      html = CrystalDocs::CodeHighlighter.highlight("  github: kemalcr/kemal", "yaml")

      html.should eq(%(  <span class="m">github:</span> <span class="s">kemalcr/kemal</span>))
    end

    it "colours a quoted key and a quoted value" do
      html = CrystalDocs::CodeHighlighter.highlight(%("a key": "a value"), "yaml")

      html.should eq(%(<span class="m">&quot;a key&quot;:</span> <span class="s">&quot;a value&quot;</span>))
    end

    it "colours an unquoted plain scalar as a string" do
      CrystalDocs::CodeHighlighter.highlight("license: MIT", "yaml")
        .should eq(%(<span class="m">license:</span> <span class="s">MIT</span>))
    end

    it "colours an integer and a float as numbers" do
      CrystalDocs::CodeHighlighter.highlight("count: 42", "yaml")
        .should contain(%(<span class="n">42</span>))
      CrystalDocs::CodeHighlighter.highlight("ratio: 3.14", "yaml")
        .should contain(%(<span class="n">3.14</span>))
      CrystalDocs::CodeHighlighter.highlight("delta: -5", "yaml")
        .should contain(%(<span class="n">-5</span>))
    end

    it "colours the boolean and null spellings YAML accepts as keywords" do
      {"true", "false", "yes", "no", "on", "off", "null", "~"}.each do |literal|
        CrystalDocs::CodeHighlighter.highlight("flag: #{literal}", "yaml")
          .should contain(%(<span class="k">#{literal}</span>))
      end
    end

    it "colours a full-line comment" do
      CrystalDocs::CodeHighlighter.highlight("# top level note", "yaml")
        .should eq(%(<span class="c"># top level note</span>))
    end

    it "colours a trailing comment after a value, keeping the gap between them plain" do
      html = CrystalDocs::CodeHighlighter.highlight("port: 8080 # the default", "yaml")

      html.should eq(
        %(<span class="m">port:</span> <span class="n">8080</span> <span class="c"># the default</span>)
      )
    end

    it "colours an anchor and an alias as a named reference" do
      html = CrystalDocs::CodeHighlighter.highlight("a: &base\nb: *base", "yaml")

      html.should contain(%(<span class="t">&amp;base</span>))
      html.should contain(%(<span class="t">*base</span>))
    end

    it "colours an anchored inline value on both halves" do
      html = CrystalDocs::CodeHighlighter.highlight("key: &name value", "yaml")

      html.should eq(
        %(<span class="m">key:</span> <span class="t">&amp;name</span> <span class="s">value</span>)
      )
    end

    it "colours the document start and end markers" do
      html = CrystalDocs::CodeHighlighter.highlight("---\nname: kemal\n...", "yaml")

      html.should contain(%(<span class="o">---</span>))
      html.should contain(%(<span class="o">...</span>))
    end

    it "keeps a sequence dash plain and colours the item after it" do
      html = CrystalDocs::CodeHighlighter.highlight("items:\n  - one\n  - 2", "yaml")

      html.should contain("  - <span class=\"s\">one</span>")
      html.should contain("  - <span class=\"n\">2</span>")
    end

    it "leaves a flow collection uncoloured rather than guessing what is inside it" do
      html = CrystalDocs::CodeHighlighter.highlight("list: [a, b, c]", "yaml")

      html.should eq(%(<span class="m">list:</span> [a, b, c]))
    end

    it "leaves a block scalar header uncoloured" do
      CrystalDocs::CodeHighlighter.highlight("body: |", "yaml")
        .should eq(%(<span class="m">body:</span> |))
      CrystalDocs::CodeHighlighter.highlight("body: >-", "yaml")
        .should eq(%(<span class="m">body:</span> &gt;-))
    end

    it "escapes a value exactly once" do
      html = CrystalDocs::CodeHighlighter.highlight("name: Q&A", "yaml")

      html.should contain(%(<span class="s">Q&amp;A</span>))
      html.should_not contain("&amp;amp;")
    end
  end

  describe "shell" do
    it "colours the command name at the head of a line" do
      CrystalDocs::CodeHighlighter.highlight("shards install", "shell")
        .should eq(%(<span class="m">shards</span> install))
    end

    it "colours a flag but not a plain argument" do
      html = CrystalDocs::CodeHighlighter.highlight("brew install --cask crystal", "bash")

      html.should contain(%(<span class="m">brew</span>))
      html.should contain(%(<span class="k">--cask</span>))
      html.should_not contain(%(<span class="m">install</span>))
      html.should_not contain(%(<span class="m">crystal</span>))
    end

    it "colours the command name again after a pipe" do
      html = CrystalDocs::CodeHighlighter.highlight("curl -fsSL https://example.com | sh", "zsh")

      html.should contain(%(<span class="m">curl</span>))
      html.should contain(%(<span class="k">-fsSL</span>))
      html.should contain(%(<span class="m">sh</span>))
      html.should_not contain(%(<span class="m">https://example.com</span>))
    end

    it "colours a comment" do
      CrystalDocs::CodeHighlighter.highlight("# install everything", "sh")
        .should eq(%(<span class="c"># install everything</span>))
    end

    it "colours a single-quoted string, spaces and all, as one token" do
      html = CrystalDocs::CodeHighlighter.highlight(%(echo 'hello world' -n), "shell")

      html.should contain(%(<span class="s">&#39;hello world&#39;</span>))
    end

    it "colours a double-quoted string with an escaped quote inside it" do
      html = CrystalDocs::CodeHighlighter.highlight(%(echo "a \\"b\\"" -n), "shell")

      html.should contain(%(<span class="s">&quot;a \\&quot;b\\&quot;&quot;</span>))
    end
  end

  describe "shell session" do
    it "colours the prompt and the command that follows it" do
      html = CrystalDocs::CodeHighlighter.highlight("$ shards install", "console")

      html.should eq(%(<span class="o">$</span> <span class="m">shards</span> install))
    end

    it "leaves an unprompted line, a command's own output, entirely plain" do
      html = CrystalDocs::CodeHighlighter.highlight(
        "$ shards install\nResolving dependencies", "shell-session"
      )

      html.should contain("Resolving dependencies")
      html.should_not contain(%(<span class="m">Resolving</span>))
    end

    it "does not mistake a variable expansion for a prompt in a plain script" do
      CrystalDocs::CodeHighlighter.highlight("echo $HOME", "bash")
        .should eq(%(<span class="m">echo</span> $HOME))
    end
  end

  describe "JSON" do
    it "gives a key and a string value different classes" do
      html = CrystalDocs::CodeHighlighter.highlight(%({"name": "kemal"}), "json")

      html.should eq(
        %({<span class="m">&quot;name&quot;</span>: <span class="s">&quot;kemal&quot;</span>})
      )
    end

    it "colours a number, including a negative exponent" do
      CrystalDocs::CodeHighlighter.highlight(%({"n": 3000}), "json")
        .should contain(%(<span class="n">3000</span>))
      CrystalDocs::CodeHighlighter.highlight(%({"n": -1.5e10}), "json")
        .should contain(%(<span class="n">-1.5e10</span>))
    end

    it "colours the three literals as keywords" do
      html = CrystalDocs::CodeHighlighter.highlight(%({"a": true, "b": false, "c": null}), "json")

      html.should contain(%(<span class="k">true</span>))
      html.should contain(%(<span class="k">false</span>))
      html.should contain(%(<span class="k">null</span>))
    end

    it "leaves structural punctuation uncoloured" do
      html = CrystalDocs::CodeHighlighter.highlight(%({"a": 1, "b": 2}), "json")

      html.should contain("{")
      html.should contain("}")
      html.should contain(", ")
    end

    it "escapes a value exactly once" do
      html = CrystalDocs::CodeHighlighter.highlight(%({"note": "Q&A"}), "json")

      html.should contain("Q&amp;A")
      html.should_not contain("&amp;amp;")
    end
  end

  describe "an unsupported or absent language" do
    it "escapes the source and never colours it" do
      html = CrystalDocs::CodeHighlighter.highlight(%(name = "kemal"), "toml")

      html.should eq(%(name = &quot;kemal&quot;))
      html.should_not contain("<span")
    end

    it "does the same for an unlabelled fence" do
      html = CrystalDocs::CodeHighlighter.highlight("plain <text> & stuff", nil)

      html.should eq("plain &lt;text&gt; &amp; stuff")
      html.should_not contain("<span")
    end

    it "matches language names case-insensitively" do
      CrystalDocs::CodeHighlighter.highlight("port: 80", "YAML")
        .should contain(%(<span class="m">port:</span>))
    end
  end

  describe "empty input" do
    it "returns an empty string for every language rather than raising" do
      {"crystal", "yaml", "json", "shell", "console", nil, "toml"}.each do |language|
        CrystalDocs::CodeHighlighter.highlight("", language).should eq("")
      end
    end
  end
end
