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
  #   /                              home
  #   /posts                         browse, or search when ?query is set
  #   /posts/:slug                   post
  #   /news                          browse
  #   /news/:slug                    post
  #   /newsletter/*                  other
  #   /contribute, /contributions/*  other
  #   /admin/*                       other
  #   /api/*                         api
  #   anything else                  other
  #
  # Two things are deliberately absent and should stay absent.
  #
  # The newsletter routes are `other` and are never counted as reading. A
  # confirmation link is a mail client following a token, not a person
  # arriving, and rolling those into traffic would inflate exactly the number
  # a writer is trying to read honestly.
  #
  # Nothing here, and nothing on the stats page this feeds, reports on
  # subscribers. A subscriber count is not audience analytics, it is the size
  # of a mailing list, and publishing it invites the wrong kind of attention
  # while telling a reader nothing about the writing.
  def self.path_kind(request : HTTP::Request) : String
    path = request.path
    return "home" if path == "/"
    return "api" if path.starts_with?("/api/")

    segments = path.split('/').reject(&.empty?)

    case segments[0]?
    when "posts", "news"
      if segments.size == 1
        search_requested?(request) ? "search" : "browse"
      else
        segments.size == 2 ? "post" : "other"
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
