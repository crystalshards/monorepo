# Rendering one version of one package, shared by the route that addresses a
# package by repository and the one that addresses it by bare name.
#
# Both routes end here on purpose. The three outcomes below are the contract
# this site makes with a reader about documentation that is built on demand,
# and having two routes render them two ways is how one of them quietly stops
# enqueueing, or starts enqueueing twice.
module Docs::VersionRendering
  include Docs::LazyBuild

  # Documentation is built the first time someone asks for a version, so three
  # outcomes are possible here and they are not interchangeable.
  #
  # All three render the same overview page. The version switcher and the build
  # badge are how a reader moves between versions and learns that a build
  # failed, so they belong on the page whatever the outcome; routing a missing
  # artifact to a separate page took both away.
  private def render_version(doc : Doc, doc_version : DocVersion)
    result = CrystalDocs::DocsLoader.build.load(doc.package_name, doc_version.version)

    if document = result.document
      # docs.total_views is no longer incremented here. Counting on render
      # counted every bot and kept no time dimension; the column is now
      # written by CrystalDocs::Stats from rolled page view data, which is
      # where real, bot-filtered, per-day numbers live.
      html Docs::VersionPage,
        doc: doc,
        doc_version: doc_version,
        document: document,
        build_request: nil
    elsif result.store_answered?
      # Storage answered and holds nothing, or holds something unparseable.
      # Either way this version needs building. Enqueue at most one, keyed on
      # the version rather than on anything from the URL, and show the reader
      # what is happening.
      #
      # Never build inline: a build clones a repository and compiles third
      # party code, so doing it in the request would hold the connection for
      # minutes and hand any visitor a denial of service for the price of a
      # few cold URLs.
      html Docs::VersionPage,
        doc: doc,
        doc_version: doc_version,
        document: nil,
        build_request: request_build(doc, doc_version)
    else
      # Storage never answered. Whether documentation exists is unknown, and a
      # build cannot fix a store that is down, so nothing is queued.
      html Docs::VersionPage,
        doc: doc,
        doc_version: doc_version,
        document: nil,
        build_request: nil
    end
  end
end
