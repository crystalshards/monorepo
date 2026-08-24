require "./spec_helper"

# The fixture is the real thing: this is what Crystal's compiler actually wrote
# for `IO.gets`, escapes and all. It is the case that shipped as literal "[2m"
# noise on the page, so it is the case the parser has to answer for.
COMPILER_ERROR = "\e[2m 2 | \e[22m\e[1mIO.gets\e[22m\n        \e[32;1m^---\e[39;22m\n\e[33;1mError: undefined method 'gets' for IO.class\e[39;22m"

describe Ansi do
  it "leaves plain text as a single unstyled segment" do
    segments = Ansi.parse("Hello, Crystal!\n")

    segments.size.should eq 1
    segments.first.text.should eq "Hello, Crystal!\n"
    segments.first.classes.should eq ""
  end

  it "returns nothing for empty output, so a caller can treat it uniformly" do
    Ansi.parse("").should be_empty
  end

  it "strips every escape byte out of the text it emits" do
    # The whole point. If an escape survives into a segment's text it lands on
    # the page through textContent and the visitor reads "[2m" again.
    segments = Ansi.parse(COMPILER_ERROR)

    segments.each do |segment|
      segment.text.should_not contain("\e")
      segment.text.should_not contain("[2m")
      segment.text.should_not contain("[39;22m")
    end
  end

  it "keeps every visible character, in order" do
    # Parsing must not lose text. Reassembling the segments has to give back
    # exactly the compiler's message with only the escapes removed.
    rebuilt = Ansi.parse(COMPILER_ERROR).map(&.text).join

    rebuilt.should eq " 2 | IO.gets\n        ^---\nError: undefined method 'gets' for IO.class"
  end

  it "carries the compiler's own emphasis onto the segments" do
    segments = Ansi.parse(COMPILER_ERROR)

    gutter = segments.find { |segment| segment.text == " 2 | " }.should_not be_nil
    gutter.classes.should eq "ansi-dim"

    source = segments.find { |segment| segment.text == "IO.gets" }.should_not be_nil
    source.classes.should eq "ansi-bold"

    caret = segments.find { |segment| segment.text == "^---" }.should_not be_nil
    caret.classes.should contain "ansi-green"
    caret.classes.should contain "ansi-bold"

    error = segments.find { |segment| segment.text.starts_with?("Error:") }.should_not be_nil
    error.classes.should contain "ansi-yellow"
    error.classes.should contain "ansi-bold"
  end

  it "composes only class names it chose itself" do
    # Compiler output must never be able to invent a class. Every class this
    # parser emits comes from a closed set, so a hostile escape sequence
    # cannot reach into the stylesheet or the markup.
    allowed = ["ansi-bold", "ansi-dim"] + Ansi::COLORS.values.map { |name| "ansi-#{name}" }

    hostile = "\e[999m\e[1;38;5;200mx\e[0m\e[31my"
    Ansi.parse(hostile).each do |segment|
      segment.classes.split(' ').reject(&.empty?).each do |name|
        allowed.should contain name
      end
    end
  end

  it "resets on 0 and on a bare escape" do
    Ansi.parse("\e[1mbold\e[0mplain").map(&.classes).should eq ["ansi-bold", ""]
    Ansi.parse("\e[1mbold\e[mplain").map(&.classes).should eq ["ansi-bold", ""]
  end

  it "clears bold and dim on 22, and colour on 39, independently" do
    Ansi.parse("\e[1;31ma\e[22mb").map(&.classes).should eq ["ansi-bold ansi-red", "ansi-red"]
    Ansi.parse("\e[1;31ma\e[39mb").map(&.classes).should eq ["ansi-bold ansi-red", "ansi-bold"]
  end

  it "maps bright colours onto the same palette as their base" do
    Ansi.parse("\e[91ma").first.classes.should eq "ansi-red"
    Ansi.parse("\e[31ma").first.classes.should eq "ansi-red"
  end

  it "drops sequences that are not SGR rather than printing them" do
    # A cursor move or a screen clear means nothing in a div, and printing it
    # raw is exactly the defect being fixed. Text either side must survive.
    Ansi.parse("before\e[2Jafter").map(&.text).join.should eq "beforeafter"
    Ansi.parse("a\e[10;20Hb").map(&.text).join.should eq "ab"
  end

  it "does not emit a segment for a style that covers no text" do
    # The compiler ends lines with a reset. That must not add an empty span.
    Ansi.parse("\e[1mx\e[22m").size.should eq 1
  end

  it "survives a truncated escape sequence at the end of the stream" do
    # Output can be cut off mid-sequence when a submission is killed.
    Ansi.parse("text\e[").map(&.text).join.should eq "text"
    Ansi.parse("text\e").map(&.text).join.should eq "text"
  end

  it "knows whether output carries any styling at all" do
    Ansi.styled?("plain").should be_false
    Ansi.styled?(COMPILER_ERROR).should be_true
  end
end
