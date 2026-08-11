require "../../spec_helper"

# Job descriptions are rendered through `raw`, so ATS-supplied markup has to
# be inert before it is stored. The guarantee is blunt on purpose: no angle
# brackets survive, however many times the input was escaped.
describe CrystalGigs::Ats::Html do
  describe ".to_text" do
    it "strips tags and keeps the words" do
      CrystalGigs::Ats::Html.to_text("<p>Hello <b>world</b></p>").should eq("Hello world")
    end

    it "unescapes markup that arrived entity-escaped, then strips it" do
      CrystalGigs::Ats::Html.to_text("&lt;p&gt;Hello&lt;/p&gt;").should eq("Hello")
    end

    it "leaves nothing bracket-shaped behind even when doubly escaped" do
      result = CrystalGigs::Ats::Html.to_text("&amp;lt;script&amp;gt;alert(1)&amp;lt;/script&amp;gt;")

      result.should_not contain("<")
      result.should_not contain(">")
    end

    it "removes a script element outright" do
      result = CrystalGigs::Ats::Html.to_text("<p>Safe</p><script>alert('x')</script>")

      result.should contain("Safe")
      result.should_not contain("<")
      result.should_not contain(">")
    end

    it "turns list items into dashes" do
      CrystalGigs::Ats::Html.to_text("<ul><li>One</li><li>Two</li></ul>")
        .should eq("- One\n- Two")
    end

    it "keeps paragraph breaks and collapses the rest of the whitespace" do
      CrystalGigs::Ats::Html.to_text("<p>One</p>\n\n\n<p>Two</p>").should eq("One\n\nTwo")
    end

    it "decodes entities inside the text" do
      CrystalGigs::Ats::Html.to_text("<p>Ben &amp; Jerry&#39;s</p>").should eq("Ben & Jerry's")
    end

    it "replaces non-breaking spaces" do
      CrystalGigs::Ats::Html.to_text("<p>a&nbsp;b</p>").should eq("a b")
    end

    it "returns an empty string for nil" do
      CrystalGigs::Ats::Html.to_text(nil).should eq("")
    end
  end

  describe ".join_all" do
    it "joins the fragments it was given and drops the blanks" do
      CrystalGigs::Ats::Html.join_all(["<p>One</p>", nil, "", "<p>Two</p>"])
        .should eq("One\n\nTwo")
    end
  end
end
