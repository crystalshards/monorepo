require "../spec_helper"

describe AuthorIdentity do
  describe ".display_name" do
    it "keeps the name and drops the bracketed address" do
      AuthorIdentity.display_name("Ary Borenszweig <ary@example.com>").should eq("Ary Borenszweig")
    end

    it "never includes the address in its output" do
      AuthorIdentity.display_name("Ary Borenszweig <ary@example.com>").should_not contain("ary@example.com")
      AuthorIdentity.display_name("Ary Borenszweig <ary@example.com>").should_not contain("@")
    end

    it "leaves a name with no address unchanged" do
      AuthorIdentity.display_name("Ary Borenszweig").should eq("Ary Borenszweig")
    end

    it "drops an unbracketed address that follows a name" do
      name = AuthorIdentity.display_name("Ary Borenszweig ary@example.com")

      name.should eq("Ary Borenszweig")
      name.should_not contain("@")
    end

    it "drops a parenthesised address" do
      AuthorIdentity.display_name("Ary Borenszweig (ary@example.com)").should eq("Ary Borenszweig")
    end

    it "drops every address when an entry carries more than one" do
      name = AuthorIdentity.display_name("Ary Borenszweig <ary@example.com>, ary@work.example")

      name.should eq("Ary Borenszweig")
      name.should_not contain("@")
    end

    it "renders a bare address as the placeholder, never any part of it" do
      name = AuthorIdentity.display_name("ary.borenszweig@example.com")

      name.should eq("unnamed author")
      name.should_not contain("ary")
      name.should_not contain("@")
    end

    it "renders a bracketed address with no name as the placeholder" do
      name = AuthorIdentity.display_name("<ary@example.com>")

      name.should eq("unnamed author")
      name.should_not contain("ary")
    end

    it "falls back to the placeholder when nothing but punctuation is left" do
      AuthorIdentity.display_name("<>").should eq("unnamed author")
    end

    it "keeps punctuation that belongs to the name" do
      AuthorIdentity.display_name("Borenszweig, Ary <ary@example.com>").should eq("Borenszweig, Ary")
    end

    it "strips surrounding whitespace" do
      AuthorIdentity.display_name("  Ary Borenszweig <ary@example.com>  ").should eq("Ary Borenszweig")
    end

    it "resolves at the last bracket pair when a name itself contains one" do
      name = AuthorIdentity.display_name("Team <Ops> <ops@example.com>")

      name.should eq("Team <Ops>")
      name.should_not contain("@")
    end
  end
end
