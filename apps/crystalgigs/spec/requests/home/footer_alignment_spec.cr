require "../../spec_helper"

# Everything in the footer's bottom row sits in one column to the right of the
# collective's mark, centred against it.
#
# The copyright used to be a sibling paragraph above the seal, flush with the
# container's left edge. Measured on the live page before this: its centre line
# was 37px above the seal's and it started 70px left of the text the seal is
# actually paired with, so the row read as a stray mark under a line of prose
# rather than as one lockup.
#
# Asserted on structure rather than pixels: the claim is that the copyright is
# INSIDE the seal's copy block, which is what puts it right of the mark and
# inside the centred row. A layout spec that measured positions would pass on a
# page where the copyright had drifted back out into its own paragraph of the
# same width.
describe "the footer's bottom row" do
  it "keeps the copyright inside the block beside the mark" do
    response = BrowserClient.exec(Home::Index)

    body = response.body
    copy_start = body.index(%(<span class="tbc-seal-copy">)).not_nil!
    copy_end = body.index("</span>", copy_start).not_nil!
    block = body[copy_start..copy_end]

    block.should contain("CrystalGigs. Part of the Crystal ecosystem.")
    block.should contain("The Bushido Collective builds and maintains this site.")

    # And not as a paragraph of its own outside it, which is where it was.
    body.should_not contain(%(<p>© ))
  end
end
