require "../../../spec_helper"

private def suggestion_names(response) : Array(String)
  JSON.parse(response.body)["suggestions"].as_a.map(&.["name"].as_s)
end

# The typeahead behind the masthead field.
#
# It answers a different question from `Api::Shards::Index`, and the examples
# that matter are the ones about what it refuses to do: ask on one character,
# return an unbounded list, or match in the middle of a name. All three are
# what keeps a per-keystroke endpoint cheap.
describe Api::Shards::Suggestions do
  it "offers nothing until the term reaches the minimum length" do
    ShardFactory.create &.name("kemal").at("github.com", "kemalcr", "kemal")

    response = ApiClient.exec(Api::Shards::Suggestions.with(query: "k"))

    response.status.should eq(HTTP::Status.new(200))
    suggestion_names(response).should be_empty
  end

  it "offers matches once it does" do
    ShardFactory.create &.name("kemal").at("github.com", "kemalcr", "kemal")
    ShardFactory.create &.name("granite").at("github.com", "amberframework", "granite")

    response = ApiClient.exec(Api::Shards::Suggestions.with(query: "ke"))

    suggestion_names(response).should eq(["kemal"])
  end

  it "matches the repository slug, so an owner's shards are reachable by typing the host" do
    ShardFactory.create &.name("kemal").at("github.com", "kemalcr", "kemal")
    ShardFactory.create &.name("granite").at("gitlab.com", "amberframework", "granite")

    response = ApiClient.exec(Api::Shards::Suggestions.with(query: "gitlab.com/amber"))

    suggestion_names(response).should eq(["granite"])
  end

  it "ignores case, in the term and in the row" do
    ShardFactory.create &.name("Kemal").at("github.com", "kemalcr", "kemal")

    response = ApiClient.exec(Api::Shards::Suggestions.with(query: "kEm"))

    suggestion_names(response).should eq(["Kemal"])
  end

  # Prefixes, not substrings. The search page behind the Enter key still
  # matches anywhere; this one is guessing at a name the reader is part way
  # through spelling, and it is the only shape a btree index can serve.
  it "matches the start of a name rather than anywhere in it" do
    ShardFactory.create &.name("crystal-kemal").at("github.com", "someone", "crystal-kemal")

    response = ApiClient.exec(Api::Shards::Suggestions.with(query: "kemal"))

    suggestion_names(response).should be_empty
  end

  it "returns at most eight, however many match" do
    12.times do |index|
      ShardFactory.create &.name("kemal-plugin-#{index}")
        .at("github.com", "kemalcr", "kemal-plugin-#{index}")
    end

    response = ApiClient.exec(Api::Shards::Suggestions.with(query: "kemal"))

    suggestion_names(response).size.should eq(ShardSuggestions::LIMIT)
  end

  # LIKE's own wildcards, escaped. Unescaped, "%" is every row: the one term a
  # reader can type that turns a bounded index range into a full scan.
  it "treats a wildcard character as a character" do
    ShardFactory.create &.name("kemal").at("github.com", "kemalcr", "kemal")

    response = ApiClient.exec(Api::Shards::Suggestions.with(query: "%e"))

    suggestion_names(response).should be_empty
  end

  # The row's own URL, so clicking a suggestion lands exactly where clicking
  # the same shard's card would.
  it "carries the shard's path and repository" do
    ShardFactory.create &.name("kemal").at("github.com", "kemalcr", "kemal")

    response = ApiClient.exec(Api::Shards::Suggestions.with(query: "kemal"))

    suggestion = JSON.parse(response.body)["suggestions"].as_a.first
    suggestion["path"].should eq("/shards/github.com/kemalcr/kemal")
    suggestion["repository"].should eq("github.com/kemalcr/kemal")
  end

  # Most rows have no star count, so without the name and id tiebreakers the
  # order of a tied page is whatever the plan happened to produce and the list
  # can reshuffle under the reader's arrow keys between two keystrokes.
  it "puts the measured shard above the unmeasured ones" do
    ShardFactory.create &.name("kemal-a").at("github.com", "one", "kemal-a")
    ShardFactory.create &.name("kemal-z").at("github.com", "two", "kemal-z").github_stars(900)

    response = ApiClient.exec(Api::Shards::Suggestions.with(query: "kemal"))

    suggestion_names(response).should eq(["kemal-z", "kemal-a"])
  end
end
