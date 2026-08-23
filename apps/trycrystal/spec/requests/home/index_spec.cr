require "../../spec_helper"

describe Home::Index do
  it "greets a new visitor with the welcome and lesson one, server rendered" do
    response = BrowserClient.exec(Home::Index)

    response.status_code.should eq 200
    body = response.body
    body.should contain("Type the line below and press Enter")
    body.should contain("Lesson 1 of 3.")
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
