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
  #   /                        home
  #   /jobs                    browse, or search when ?query is set
  #   /jobs/new                other, it is the posting form and not a posting
  #   /jobs/:id                job
  #   /jobs/:id/payment        other
  #   /jobs/:id/checkout       other
  #   /pricing                 other
  #   /api/*                   api
  #   anything else            other
  #
  # Everything past the posting itself is deliberately `other`, and that is a
  # commercial decision rather than a tidying one. This is a job board: the
  # path from a posting to its payment IS the funnel, and a public stats page
  # that grouped those paths would publish the conversion rate of a board that
  # charges to post. Audience numbers are the site's to share. An employer's
  # response rate is the employer's.
  def self.path_kind(request : HTTP::Request) : String
    path = request.path
    return "home" if path == "/"
    return "api" if path.starts_with?("/api/")

    segments = path.split('/').reject(&.empty?)
    return "other" unless segments[0]? == "jobs"

    case segments.size
    when 1 then search_requested?(request) ? "search" : "browse"
    when 2 then segments[1]? == "new" ? "other" : "job"
    else        "other"
    end
  end

  # A listing with a query is a search; the same listing without one is a
  # browse. The term itself is never read into the row, only that there
  # was one.
  private def self.search_requested?(request : HTTP::Request) : Bool
    !request.query_params["query"]?.presence.nil?
  end
end
