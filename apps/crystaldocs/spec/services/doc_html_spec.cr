require "../spec_helper"

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
end
