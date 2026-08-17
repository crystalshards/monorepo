require "../spec_helper"

# Every asset app.css points at has to exist in public/.
#
# A stylesheet reference to a missing file fails silently in the worst way for
# a mask: `background-color: currentColor` with a mask that resolves to nothing
# paints nothing at all, so the element keeps its box, the page keeps its
# layout, and the mark simply is not there. No console error a spec can see, no
# failed request anyone watches. This is the check that a rename or a delete
# has to get past.
describe "app.css assets" do
  it "resolves every url() it references to a file in public/" do
    public_dir = Path[__DIR__].parent.parent / "public"
    css = File.read(public_dir / "css" / "app.css")

    referenced = css.scan(/url\("(\/[^")]+)"\)/).map(&.[1]).uniq!
    referenced.size.should be > 0

    missing = referenced.reject do |ref|
      File.exists?(public_dir / ref.lchop('/'))
    end

    missing.should eq([] of String)
  end

  it "still points the collective's mark at a file that is there" do
    public_dir = Path[__DIR__].parent.parent / "public"
    css = File.read(public_dir / "css" / "app.css")

    css.should contain("/images/tbc-mark.svg")
    File.exists?(public_dir / "images" / "tbc-mark.svg").should be_true
  end
end
