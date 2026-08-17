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
  #   /                                home
  #   /shards                          browse, or search when ?query is set
  #   /shards/:shard_name              package
  #   /shards/:host/:owner/:repo       package
  #   /shards/:host/:owner/:repo/...   package (versions of the same shard)
  #   /api/*                           api
  #   anything else                    other
  def self.path_kind(request : HTTP::Request) : String
    path = request.path
    return "home" if path == "/"
    return "api" if path.starts_with?("/api/")

    segments = path.split('/').reject(&.empty?)

    case segments[0]?
    when "shards"
      if segments.size == 1
        search_requested?(request) ? "search" : "browse"
      else
        "package"
      end
    else
      "other"
    end
  end

  # A listing with a query is a search; the same listing without one is a
  # browse. The term itself is never read into the row, only that there
  # was one.
  private def self.search_requested?(request : HTTP::Request) : Bool
    !request.query_params["query"]?.presence.nil?
  end
end
