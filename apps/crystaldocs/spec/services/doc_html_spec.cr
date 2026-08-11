require "../spec_helper"

# A hash link is only fixed when something on the page answers to it, so the
# specs below check the pair rather than either half on its own.
private def fragment_targets(html : String) : Array(String)
  html.scan(/href="#([^"]*)"/).map(&.[1])
end

private def element_ids(html : String) : Array(String)
  html.scan(/id="([^"]*)"/).map(&.[1])
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
end
