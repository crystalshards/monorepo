require "./spec_helper"

# The product runs whatever a visitor types and prints whatever it produced.
# Rendering any of that as markup would be the hole, so the console script
# has exactly one way to put a string on the page: textContent. This guards
# that property at the only level it can be guarded without a browser, the
# shipped file itself, because a single innerHTML added later would reopen
# it silently and no unit test of the server would notice.
#
# The browser half of the proof (that a submission printing a script tag
# renders as visible text and executes nothing) is a separate exercise
# against a real page; this is the regression gate that keeps it true.
describe "the console script's DOM sinks" do
  script = File.read(Path[__DIR__, "..", "public", "js", "console.js"])

  # Positive control: the pattern this spec bans must actually be findable
  # in text that contains it, otherwise the assertions below pass on a typo
  # and guard nothing.
  it "can detect an unsafe sink at all" do
    UNSAFE_SINKS.any? { |sink| "node.innerHTML = evil;".includes?(sink) }.should be_true
  end

  it "never inserts a string as markup" do
    found = UNSAFE_SINKS.select { |sink| script.includes?(sink) }

    found.should be_empty
  end

  it "renders through textContent, and does so more than once" do
    # More than once because a single use could be an unrelated read; the
    # console writes echoes, output, values and reactions this way.
    script.scan("textContent").size.should be > 3
  end
end

UNSAFE_SINKS = [
  "innerHTML",
  "outerHTML",
  "insertAdjacentHTML",
  "document.write",
  "createContextualFragment",
  "eval(",
]
