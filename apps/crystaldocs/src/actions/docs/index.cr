# The catalogue of shards, which is the registry's list and not this app's.
#
# This page used to browse the `docs` table, which is populated on demand by
# `PackageRegistration` when somebody opens a package's version URL. That made
# the list, its total and its pagination a report on this site's own traffic
# while presenting itself as the set of Crystal shards, and it is why the two
# sites reported different totals for the same ecosystem.
class Docs::Index < BrowserAction
  param page : Int32 = 1
  param query : String?

  get "/docs" do
    per_page = 20
    # A page below the first is not a page. Left unclamped it produces a
    # negative OFFSET, which Postgres rejects outright.
    current_page = page < 1 ? 1 : page

    catalogue = CrystalDocs::PackageCatalogue.page(query, current_page, per_page)

    html Docs::IndexPage,
      entries: catalogue.entries,
      available: catalogue.available?,
      query: query,
      page: current_page,
      per_page: per_page,
      total_count: catalogue.total
  end
end
