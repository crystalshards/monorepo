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

    it "renders a bare address as its local part, never the address itself" do
      name = AuthorIdentity.display_name("ary@example.com")

      name.should eq("ary")
      name.should_not contain("@")
    end

    it "renders a bracketed address with no name as its local part" do
      name = AuthorIdentity.display_name("<ary@example.com>")

      name.should eq("ary")
      name.should_not contain("@")
    end

    it "falls back to a neutral placeholder when even the local part is empty" do
      AuthorIdentity.display_name("<>").should eq("unnamed author")
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
