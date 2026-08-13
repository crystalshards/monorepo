# What the masthead field offers while the reader is still typing.
#
# Its own endpoint rather than a mode of `Api::Shards::Index`, because the two
# are asked different questions and cost different amounts. The index paginates,
# counts the whole match set and preloads every version of every row on the
# page; this returns at most eight names and never counts anything, because it
# runs once per keystroke.
#
# A term below the minimum, or none at all, is an empty list and not an error.
# The field is empty on every page load and the client asks nothing until there
# is something to ask about, so a 400 here would only ever report our own bug.
class Api::Shards::Suggestions < ApiAction
  include Api::Auth::SkipRequireAuthToken

  param query : String = ""

  get "/api/shards/suggestions" do
    suggestions = ShardSuggestions.for(query)

    json({
      suggestions: suggestions.map do |suggestion|
        {
          name: suggestion.name,
          # The repository this shard is, which is null for the legacy rows
          # that never got one. The list shows it under the name so two
          # shards called "router" are told apart.
          repository: suggestion.slug,
          path:       suggestion.path,
        }
      end,
    })
  end
end
