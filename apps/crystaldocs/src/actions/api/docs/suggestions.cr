# What the masthead field offers while the reader is still typing.
#
# Its own endpoint rather than a mode of `Api::Docs::Index`, because the two
# are asked different questions and cost different amounts. The index reads the
# registry's page and its total, then joins this app's build state onto it; this
# reads at most eight names and joins nothing, because it runs once per
# keystroke.
#
# It also does not report an outage the way the index does. An empty catalogue
# is a claim that no shard exists and a client would cache it, so the index
# answers 503 rather than an empty list. An empty suggestion list makes no such
# claim: it says there is nothing to offer for what has been typed so far, and
# the reader still has a search form that submits.
class Api::Docs::Suggestions < ApiAction
  include Api::Auth::SkipRequireAuthToken

  param query : String = ""

  get "/api/docs/suggestions" do
    suggestions = CrystalDocs::PackageSuggestions.for(query)

    json({
      suggestions: suggestions.map do |suggestion|
        {
          name:       suggestion.name,
          repository: suggestion.repository,
          path:       suggestion.path,
        }
      end,
    })
  end
end
