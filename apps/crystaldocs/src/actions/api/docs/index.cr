# The catalogue, as JSON. The same list the browse page renders and from the
# same source: the registry decides which packages exist, and this app's rows
# say which of them it has built.
#
# This is the endpoint a client resolves a name against, so answering it from
# the `docs` table meant a name only resolved once somebody had already opened
# that package on the website.
class Api::Docs::Index < ApiAction
  include Api::Auth::SkipRequireAuthToken

  param page : Int32 = 1
  param per_page : Int32 = 20
  param query : String?

  get "/api/docs" do
    current_page = page < 1 ? 1 : page
    catalogue = CrystalDocs::PackageCatalogue.page(query, current_page, per_page)

    if catalogue.available?
      json(catalogue_body(catalogue, current_page))
    else
      # 503 rather than an empty list. An empty `docs` array is a claim that
      # the registry holds no matching shard, and a client that cannot tell
      # that apart from an outage will cache the absence.
      json(
        {error: "The shard index is unavailable, so the catalogue cannot be listed."},
        status: 503
      )
    end
  end

  private def catalogue_body(
    catalogue : CrystalDocs::PackageCatalogue::Page,
    current_page : Int32,
  )
    {
      docs: catalogue.entries.map do |entry|
        {
          package_name:    entry.key,
          current_version: entry.version,
          description:     entry.description,
          repository_url:  entry.repository_url,
          total_views:     entry.total_views,
          last_updated_at: entry.last_updated_at,
          created_at:      entry.created_at,
          updated_at:      entry.updated_at,
        }
      end,
      meta: {
        page:     current_page,
        per_page: per_page,
        total:    catalogue.total,
      },
    }
  end
end
