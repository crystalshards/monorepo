require "../../spec_helper"

describe Home::Index do
  it "renders the workspace: lesson one on the left, editor and output on the right" do
    response = BrowserClient.exec(Home::Index)

    response.status_code.should eq 200
    body = response.body

    # The lesson is server rendered into its own pane, so a visitor reads a
    # real lesson before any script runs.
    body.should contain("Lesson 1 of 3.")
    body.should contain(%(id="lesson-pane"))

    # Three surfaces, not one transcript. Each is asserted because the whole
    # point of the layout is that narrative, input and output do not share a
    # scroll.
    body.should contain("pane--lesson")
    body.should contain("pane--editor")
    body.should contain("pane--output")
    body.should contain(%(id="console-input"))
    body.should contain(%(id="transcript"))

    # Running is a deliberate act now, and the shortcut is named on the
    # surface rather than left for a visitor to guess.
    body.should contain("Cmd or Ctrl + Enter")
  end

  it "offers the lesson's line as a copyable example rather than only prose" do
    response = BrowserClient.exec(Home::Index)

    body = response.body
    body.should contain(%(id="copy-example"))
    body.should contain("Copy example")
  end

  it "does not tell a visitor to press Enter, because Enter is a newline now" do
    # The editor is multi-line, so Enter belongs to the text. Copy that still
    # said "press Enter" would be instructions for a product that no longer
    # exists, which is worse than no instructions.
    response = BrowserClient.exec(Home::Index)

    response.body.should_not contain("press Enter")
  end

  it "links the two sites the colophon names" do
    # They are places you should be able to go, not decoration. Asserted as
    # real anchors so a future copy edit that flattens them back into prose
    # fails here rather than quietly losing the links.
    response = BrowserClient.exec(Home::Index)

    body = response.body
    body.should contain(%(<a href="https://crystalshards.org">crystalshards.org</a>))
    body.should contain(%(<a href="https://crystal-lang.org">crystal-lang.org</a>))
  end

  it "escapes the lesson's code sample instead of emitting it as markup" do
    # The server-rendered transcript is the one place static prose reaches
    # the page through Lucky's escaping. The sample's double quotes must
    # arrive as entities; the raw text of the line must not appear unescaped
    # anywhere a browser would read as an attribute or a tag.
    response = BrowserClient.exec(Home::Index)

    body = response.body
    body.should contain(%(puts &quot;Hello, Crystal!&quot;))
    body.should_not contain(%(>puts "Hello, Crystal!"))
  end

  it "ships the lesson list for the console script, without any checks" do
    # The boot island lets the script resume a session client side; the
    # checks stay server side on purpose. If a check proc ever serializes
    # into this island, the browser would be deciding what passes.
    response = BrowserClient.exec(Home::Index)

    body = response.body
    body.should contain("trycrystal-console")
    # The quoted form, so a spellcheck attribute cannot masquerade as a
    # serialized check.
    body.should_not contain(%("check"))
  end

  it "tells scriptless visitors the truth rather than a silent form" do
    response = BrowserClient.exec(Home::Index)

    response.body.should contain("needs JavaScript")
  end
end
