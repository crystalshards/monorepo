# The enqueue half of building documentation on first request.
#
# Included by Docs::Version and by nothing else, deliberately. With lazy
# generation every URL that can commission a build is a spend endpoint, so
# there is exactly one such URL: the version route, where both the package and
# the version have been checked against the database and the set of reachable
# URLs is therefore finite.
#
# The enqueue is keyed on (package, version) and never on the requested path.
# That is the property that makes this safe to expose: a crawler walking ten
# thousand invented paths under one unbuilt version still commissions the same
# finite set of builds, because every key is derived from the version, not from
# the URL. Spend is bounded by the number of real versions.
#
# That set is the version itself, its direct runtime dependencies at the
# releases it resolves to, and one standard library version. It is not the
# whole dependency closure: `DocBuildRequests#request_with_dependencies`
# explains why a reader's page load must not stand in front of a graph walk,
# and how the closure fills in over successive commissionings instead.
module Docs::LazyBuild
  # Short enough that a small shard's build feels immediate, long enough that
  # a reader who leaves the tab open is not generating a request per second.
  # Nothing about the build depends on this; the page polls storage, it does
  # not drive the builder.
  REFRESH_SECONDS = 5

  # Registers the version, commissions it along with its direct dependencies
  # and the standard library it targets, and returns the request for the
  # version the reader actually asked for. Safe to call on every cache miss:
  # each combination is enqueued at most once, and the database rather than
  # this process decides which of them are new.
  private def request_build(doc : Doc, doc_version : DocVersion) : DocBuildRequest
    build_request = CrystalDocs::DocBuildRequests.new.request_with_dependencies(
      doc.package_name,
      doc_version.version
    )

    schedule_refresh(build_request)
    build_request
  end

  # The Refresh response header is a meta refresh without editing the Head
  # component every page in this app shares. Set only while the build is in
  # flight: reloading a failed build every few seconds shows the reader the
  # same failure again and asks a question the retry floor has already
  # answered.
  private def schedule_refresh(build_request : DocBuildRequest) : Int32?
    return nil unless build_request.in_flight?

    context.response.headers["Refresh"] = REFRESH_SECONDS.to_s
    REFRESH_SECONDS
  end
end
