class Docs::VersionPage < MainLayout
  needs doc : Doc
  needs doc_version : DocVersion
  needs document : CrystalDocs::DocsDocument?

  # Every version this site can name, built or not. Supplied by the action
  # because it reaches the registry database, which a page must not do.
  needs known_versions : Array(CrystalDocs::VersionCatalogue::Entry)

  # Present only when there is no document and a build has been asked for.
  # Nil when the document rendered, and nil when storage never answered,
  # because nothing was queued in either case.
  needs build_request : DocBuildRequest?

  def page_title
    "#{doc.package_name} #{doc_version.version}"
  end

  def content
    div class: "docs-shell" do
      mount Components::DocsSidebarNav,
        doc: doc,
        doc_version: doc_version,
        types: document.try(&.all_types) || [] of CrystalDocs::DocType,
        current_full_name: nil,
        documented: !document.nil?

      div class: "docs-main" do
        render_header

        if parsed = document
          render_readme(parsed)
          render_type_index(parsed)
        else
          render_unavailable
        end
      end
    end
  end

  # Breadcrumbs, the version switcher and the build badge predate the JSON
  # renderer and are still the only way to move between versions or to see
  # that a build failed, so they survive the rewrite. The switcher's label
  # association in particular was an accessibility fix; do not drop it again.
  private def render_header
    mount Components::Breadcrumb, items: [
      Components::Breadcrumb::BreadcrumbItem.new("Home", "/"),
      Components::Breadcrumb::BreadcrumbItem.new("Documentation", "/docs"),
      Components::Breadcrumb::BreadcrumbItem.new(doc.package_name, CrystalDocs::PackagePaths.package_path(doc.package_name)),
      Components::Breadcrumb::BreadcrumbItem.new(doc_version.version, CrystalDocs::PackagePaths.version_path(doc.package_name, doc_version.version)),
    ]

    header class: "docs-type-header" do
      span class: "docs-kind" do
        text "package"
      end

      h1 class: "docs-type-name" do
        text doc.package_name
      end

      para class: "docs-ancestry" do
        text doc_version.version

        if published = doc_version.published_at
          text " / published #{published.to_s("%b %-d, %Y")}"
        end

        if url = doc.repository_url
          text " / "
          a href: url, class: "docs-ancestry-link docs-external", target: "_blank", rel: "noopener" do
            text "repository"
          end
        end
      end

      render_version_switcher
      render_build_status

      if description = doc.description
        para class: "docs-summary" do
          text description
        end
      end
    end
  end

  # The label carries `for` and the select carries the matching `id`. A screen
  # reader announced this as a bare "combo box" before that was fixed.
  #
  # Two groups, because "documented" and "we could build this if you asked"
  # are different offers and a flat list makes them look identical. A reader
  # picking from the second group gets the build-in-progress page, which is
  # the honest outcome rather than a 404.
  private def render_version_switcher
    return if known_versions.empty?

    built, unbuilt = known_versions.partition(&.built?)

    div class: "docs-version-switcher" do
      label "Version:", for: "version-select"

      tag "select", id: "version-select", onchange: "window.location.href = this.value" do
        render_version_group("Documented", built)
        render_version_group("Not built yet", unbuilt)
      end
    end
  end

  # `group_label` rather than `label`: Lucky's HTML builder defines `label` as
  # a tag method on this class, and a parameter of that name shadows it.
  private def render_version_group(group_label : String, entries : Array(CrystalDocs::VersionCatalogue::Entry))
    return if entries.empty?

    tag "optgroup", label: group_label do
      entries.each do |entry|
        href = CrystalDocs::PackagePaths.version_path(doc.package_name, entry.version)

        if entry.version == doc_version.version
          tag("option", value: href, selected: "selected") { text entry.version }
        else
          tag("option", value: href) { text entry.version }
        end
      end
    end
  end

  # A failed or pending build is the explanation for a thin page, so it is
  # stated rather than left for the reader to infer.
  #
  # Said once, though. This page has a build-state section further down that
  # explains what is happening in a sentence, and this badge is a second voice
  # saying a shorter version of the same thing from a different column. They
  # disagreed constantly: a stale claim reclaimed for retry moves the request
  # row back to pending while the version row still holds the failure, so the
  # page read "Build: failed" directly above "Documentation is being built",
  # and the sidebar added "This package defines no public types" underneath.
  # Three claims, one page, no two agreeing.
  #
  # The build-state section wins because it can say what happens next. This
  # badge only appears when there is no such section to defer to.
  private def render_build_status
    return if document
    return if build_request

    para class: "docs-build-status" do
      text "Build: "
      strong doc_version.build_status.to_s
    end
  end

  # The README is raw Markdown in the document, and it was written by whoever
  # published the shard, so it is rendered and sanitised rather than trusted.
  # A relative image or link in it is also resolved against the repository
  # the version being read was published from, because the page renders on
  # our own origin rather than the shard's.
  #
  # `ref` is the commit the artifact was actually built from, not
  # `doc_version.version`: the registry stores "1.2.3" while a repository's
  # own tag is often "v1.2.3", so the version string alone 404s against
  # GitHub as often as it works, and where it does resolve nothing pins it
  # to the exact revision this artifact documents rather than to whatever
  # that tag currently points at. A version built before this column existed
  # has no stored commit, and DocHtml already drops a relative reference
  # rather than resolve it against nothing.
  private def render_readme(parsed : CrystalDocs::DocsDocument)
    body = parsed.body
    return unless body && !body.empty?

    section class: "docs-section" do
      div class: "docs-readme" do
        raw CrystalDocs::DocHtml.markdown(body, repository: repository_slug, ref: doc_version.source_commit_sha)
      end
    end
  end

  # The registry hands every shard it indexes a host qualified identity
  # ("github.com/owner/repo"), and that identity is the repository a
  # README's relative reference has to be read against, because it is
  # where the file actually lives. `doc.package_name` already carries it
  # for every row the registry created. The standard library is the one
  # row that still carries a bare key instead, so its repository is named
  # explicitly here rather than left unresolved.
  private def repository_slug : String?
    return doc.package_name if CrystalDocs::PackagePaths.canonical?(doc.package_name)
    return Docs::CoreRepository::CORE_REPOSITORY if doc.package_name == CrystalDocs::CORE_PACKAGE

    nil
  end

  private def render_type_index(parsed : CrystalDocs::DocsDocument)
    types = parsed.top_level_types

    section class: "docs-section" do
      h2 class: "docs-section-heading" do
        text "API"
      end

      if types.empty?
        para do
          text "This version publishes no documented types."
        end
      else
        ul class: "docs-toc" do
          types.each do |type|
            li do
              a(
                href: CrystalDocs::PackagePaths.type_path(doc.package_name, doc_version.version, type.url_path),
                class: "docs-toc-link"
              ) do
                text type.full_name
              end

              if summary = type.summary.presence
                div class: "docs-member-doc" do
                  raw CrystalDocs::DocHtml.sanitize(summary)
                end
              end
            end
          end
        end
      end
    end
  end

  # No document. The version exists, so say what is actually wrong instead of
  # implying the package was never documented.
  #
  # With documentation built on first request there are two different reasons
  # to be here, and conflating them is what made the old copy useless: either
  # a build has been asked for and its state is known, or storage could not be
  # reached and nothing is known at all.
  private def render_unavailable
    section class: "docs-section build-state" do
      if request = build_request
        render_build_state(request)
      else
        render_storage_unavailable
      end

      para do
        a "Browse the other versions", href: CrystalDocs::PackagePaths.package_path(doc.package_name)
      end
    end
  end

  # A live region: while a build runs the page reloads itself, and this is the
  # only part that changes. Without it a screen reader re-reads the whole
  # document with no indication of what moved.
  private def render_build_state(request : DocBuildRequest)
    h2 class: "docs-section-heading" do
      text build_heading(request)
    end

    div class: "build-state-status", role: "status", "aria-live": "polite" do
      span class: "build-status-badge #{build_badge_class(request)} build-state-badge" do
        tag "i", class: build_badge_icon(request), "aria-hidden": "true"
        text build_badge_label(request)
      end
    end

    case request.status
    when DocBuildRequest::FAILED    then render_build_failed(request)
    when DocBuildRequest::SUCCEEDED then render_artifact_missing
    when DocBuildRequest::BUILDING  then render_building
    else                                 render_queued
    end
  end

  private def render_queued
    para class: "build-state-copy" do
      text "Nobody had asked for this version before, so its documentation is "
      text "being built now. Documentation is built the first time a version "
      text "is requested rather than ahead of time for every version ever "
      text "published."
    end

    render_refresh_note
  end

  private def render_building
    para class: "build-state-copy" do
      text "The build is running: the repository is cloned, its dependencies "
      text "are installed and the API is extracted in a sandbox. Larger shards "
      text "take longer."
    end

    render_refresh_note
  end

  # The reader is told the reload button will not help, because otherwise they
  # will press it, and the retry floor is stated as a property of the system
  # rather than a timestamp to decode.
  private def render_build_failed(request : DocBuildRequest)
    para class: "build-state-copy" do
      text "The documentation build for this version ran and did not produce "
      text "anything usable. That is usually a shard that does not compile "
      text "against the Crystal version it declared."
    end

    if failed_at = request.failed_at
      para class: "build-state-meta" do
        text "Last attempt #{failed_at.to_s("%b %-d, %Y at %H:%M UTC")}"
        text " (attempt #{request.attempts})" if request.attempts > 1
      end
    end

    para class: "build-state-meta" do
      text "Reloading will not start another build. A failed version is left "
      text "alone for an hour before it can be requested again, so one shard "
      text "that cannot build does not crowd out the ones that can."
    end

    if message = request.last_error.presence
      details class: "build-state-error" do
        summary "What the builder reported"
        # Compiler output from third party code. Escaped text, never markup.
        pre { code message }
      end
    end
  end

  # The builder says it succeeded and storage says there is nothing there.
  # Surfaced rather than quietly rebuilt: an automatic retry here would erase
  # the only signal that something removed an object.
  private def render_artifact_missing
    para class: "build-state-copy" do
      text "This version was built successfully, but its documentation could "
      text "not be read back from storage. That is an inconsistency on our "
      text "side rather than a problem with the shard."
    end
  end

  private def render_storage_unavailable
    h2 class: "docs-section-heading" do
      text "Documentation could not be loaded"
    end

    para class: "build-state-copy" do
      text "The documentation store did not answer, so whether this version "
      text "has been built is unknown. Nothing has been queued, because a "
      text "build cannot fix a store that is down. Try again shortly."
    end
  end

  private def render_refresh_note
    para class: "build-state-meta" do
      text "This page refreshes every #{Docs::LazyBuild::REFRESH_SECONDS} "
      text "seconds and shows the documentation as soon as the build finishes."
    end
  end

  private def build_heading(request : DocBuildRequest) : String
    case request.status
    when DocBuildRequest::FAILED    then "Documentation could not be built"
    when DocBuildRequest::SUCCEEDED then "Documentation is missing from storage"
    else                                 "Documentation is being built"
    end
  end

  # Reuses the status tints the rest of the site already uses for build state.
  private def build_badge_class(request : DocBuildRequest) : String
    if request.in_flight?
      "status-pending"
    else
      "status-failed"
    end
  end

  # Font Awesome is already loaded for the rest of the site.
  private def build_badge_icon(request : DocBuildRequest) : String
    case request.status
    when DocBuildRequest::FAILED    then "fa-solid fa-circle-exclamation"
    when DocBuildRequest::SUCCEEDED then "fa-solid fa-triangle-exclamation"
    when DocBuildRequest::BUILDING  then "fa-solid fa-gear"
    else                                 "fa-regular fa-clock"
    end
  end

  private def build_badge_label(request : DocBuildRequest) : String
    case request.status
    when DocBuildRequest::FAILED    then "Build failed"
    when DocBuildRequest::SUCCEEDED then "Artifact missing"
    when DocBuildRequest::BUILDING  then "Building"
    else                                 "Queued"
    end
  end
end
