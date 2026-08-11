require "../spec_helper"

describe BitsHtml do
  describe ".markdown" do
    it "strips a script tag out of submitted markdown" do
      html = BitsHtml.markdown("Hello\n\n<script>alert('xss')</script>\n\nGoodbye")

      html.downcase.should_not contain("<script")
      html.should_not contain("alert('xss')")
      html.should contain("Hello")
      html.should contain("Goodbye")
    end

    it "strips an inline script tag without losing the surrounding sentence" do
      html = BitsHtml.markdown("Crystal is <script>steal()</script> fast")

      html.downcase.should_not contain("<script")
      html.should contain("Crystal is")
      html.should contain("fast")
    end

    it "strips an image with an inline error handler" do
      html = BitsHtml.markdown(%(before\n\n<img src=x onerror="alert(1)">\n\nafter))

      html.should_not contain("onerror")
      html.should_not contain("alert(1)")
    end

    it "drops a javascript link destination but keeps the text" do
      html = BitsHtml.markdown("[click me](javascript:alert(1))")

      html.should_not contain("javascript:")
      html.should contain("click me")
    end

    it "still renders ordinary markdown" do
      html = BitsHtml.markdown("# Heading\n\nSome **bold** text and a [link](https://crystal-lang.org).")

      html.should contain("<h1>")
      html.should contain("<strong>bold</strong>")
      html.should contain(%(href="https://crystal-lang.org"))
    end

    it "escapes markdown text that looks like markup" do
      html = BitsHtml.markdown("Compare `a < b` and 3<4 in prose")

      html.downcase.should_not contain("<b>")
      html.should contain("&lt;")
    end
  end

  describe ".sanitize" do
    it "drops a script element and everything inside it" do
      BitsHtml.sanitize("<script>alert(1)</script>kept").should eq("kept")
    end

    it "drops style, iframe and form controls whole" do
      BitsHtml.sanitize("<style>body{}</style>a").should eq("a")
      BitsHtml.sanitize(%(<iframe src="//evil">x</iframe>b)).should eq("b")
      BitsHtml.sanitize("<form><input name=q></form>c").should eq("c")
    end

    it "removes event handler attributes" do
      BitsHtml.sanitize(%(<p onclick="steal()">text</p>)).should eq("<p>text</p>")
    end

    it "removes a javascript scheme however it is spelled" do
      %w[
        javascript:alert(1)
        JaVaScRiPt:alert(1)
        java&#115;cript:alert(1)
        javascript&colon;alert(1)
        data:text/html,<script>alert(1)</script>
      ].each do |destination|
        result = BitsHtml.sanitize(%(<a href="#{destination}">x</a>))
        result.should eq("<a>x</a>")
      end
    end

    it "keeps http, https, mailto, relative and fragment links" do
      {
        "https://crystal-lang.org" => "https://crystal-lang.org",
        "http://example.com"       => "http://example.com",
        "mailto:hi@example.com"    => "mailto:hi@example.com",
        "/news"                    => "/news",
        "#section"                 => "#section",
        "docs/a:b"                 => "docs/a:b",
      }.each do |destination, expected|
        BitsHtml.sanitize(%(<a href="#{destination}">x</a>)).should eq(%(<a href="#{expected}">x</a>))
      end
    end

    it "unwraps an unknown element but keeps its content" do
      BitsHtml.sanitize("<marquee><b>keep</b></marquee>").should eq("<b>keep</b>")
    end

    it "closes tags the input left open" do
      BitsHtml.sanitize("<p><em>unclosed").should eq("<p><em>unclosed</em></p>")
    end

    it "ignores a closing tag with no matching open tag" do
      BitsHtml.sanitize("<b>x</i></b>").should eq("<b>x</b>")
    end

    it "treats a bare angle bracket as text" do
      BitsHtml.sanitize("a < b").should eq("a &lt; b")
    end

    it "does not double escape an entity already in an attribute" do
      BitsHtml.sanitize(%(<a href="https://x.test?a=1&amp;b=2">y</a>))
        .should eq(%(<a href="https://x.test?a=1&amp;b=2">y</a>))
    end
  end

  describe ".plain_text" do
    it "reduces third-party html to text and decodes entities" do
      BitsHtml.plain_text("<p>Fine &amp; dandy</p>").should eq("Fine & dandy")
    end

    it "drops scripts rather than exposing their source as text" do
      BitsHtml.plain_text("<script>evil()</script><p>real</p>").should eq("real")
    end

    it "truncates on a word boundary when given a limit" do
      result = BitsHtml.plain_text("<p>#{"word " * 40}</p>", 50)

      result.size.should be <= 53
      result.should end_with("...")
      result.should_not contain("<")
    end
  end
end
