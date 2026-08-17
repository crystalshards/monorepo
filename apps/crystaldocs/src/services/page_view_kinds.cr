# The routes this app serves, folded into the closed set of kinds the
# rollup groups by. Kept apart from page_views.cr, which is byte-identical
# across the four apps; this file is the per-app half of the collector.
#
# The mapping is a shape over path segments rather than a list of routes,
# because the handler runs around routing and never learns which action
# answered. Anything the classifier does not recognize is `other`, and
# anything refused upstream (a 404, an asset, the health endpoint) never
# reaches it.
module PageViews
  # This app addresses the same document two ways, and the split below is the
  # only reason the numbers mean anything:
  #
  #   /                                        home
  #   /docs                                    browse, or search when ?query is set
  #   /docs/:name                              package
  #   /docs/:name/:version                     docs_version
  #   /docs/:name/:version/:type/*rest         docs_type
  #   /docs/_/:host/:owner/:repo               package
  #   /docs/_/:host/:owner/:repo/:version      docs_version
  #   /docs/_/:host/:owner/:repo/:v/:type/...  docs_type
  #   /api/*                                   api
  #   anything else                            other
  #
  # Telling docs_version from docs_type is the whole point of the split for
  # this site: together they answer whether a reader landed on a package and
  # left, or actually read its API. Collapsing both into `package`, the way a
  # generic classifier would, would throw that away.
  #
  # The `_` sentinel is what makes the two forms need separate arithmetic: a
  # repository is three segments where a bare name is one, so the same kind
  # sits at a different depth on each path.
  def self.path_kind(request : HTTP::Request) : String
    path = request.path
    return "home" if path == "/"
    return "api" if path.starts_with?("/api/")

    segments = path.split('/').reject(&.empty?)
    return "other" unless segments[0]? == "docs"
    return search_requested?(request) ? "search" : "browse" if segments.size == 1

    # Total segment count at which the path is the package itself, counting
    # the leading "docs": "docs/_/host/owner/repo" is five, "docs/:name" is
    # two. Getting this off by one would file every package page as a version
    # and every version as a type, which is worse than not classifying at all
    # because the numbers would still look plausible.
    identity_depth = segments[1]? == "_" ? 5 : 2

    case segments.size <=> identity_depth
    when -1 then "other"
    when  0 then "package"
    else
      segments.size == identity_depth + 1 ? "docs_version" : "docs_type"
    end
  end

  # A listing with a query is a search; the same listing without one is a
  # browse. The term itself is never read into the row, only that there
  # was one.
  private def self.search_requested?(request : HTTP::Request) : Bool
    !request.query_params["query"]?.presence.nil?
  end
end
