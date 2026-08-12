# Rendering one type out of a package's docs.json, shared by the repository
# route and the bare name route.
#
# The important property, and the reason this is not simply folded into the
# version rendering: a type route never enqueues. With lazy generation any URL
# that can commission a build is a spend endpoint, and a type path is attacker
# shaped, because /docs/pkg/1.0.0/Anything/At/All parses fine and resolves to
# nothing.
module Docs::TypeRendering
  private def render_type(doc : Doc, doc_version : DocVersion, requested : String)
    document = CrystalDocs::DocsLoader.build.load(doc.package_name, doc_version.version).document

    if document.nil?
      # Either the build produced nothing or storage is unreachable. The
      # version page already tells those apart for the reader, so defer to it
      # rather than inventing a second explanation here.
      #
      # This is also where the spend bound comes from. Without the index there
      # is no way to tell an invented path from a real type, so this does not
      # pretend to; it hands off to the version route, which enqueues for the
      # version, which genuinely is missing. Enqueue is keyed on the version
      # and never on the requested path, so ten thousand invented paths under
      # one unbuilt version still commission exactly one build.
      redirect to: CrystalDocs::PackagePaths.version_path(doc.package_name, doc_version.version)
    else
      # The index is in hand, so an unknown path is known to be no type.
      type = document.find_type(requested.gsub('/', "::"))
      raise Lucky::RouteNotFoundError.new(context) if type.nil?

      html Docs::TypePage,
        doc: doc,
        doc_version: doc_version,
        document: document,
        type: type,
        linker: build_linker(doc, doc_version, document)
    end
  end

  private def build_linker(
    doc : Doc,
    doc_version : DocVersion,
    document : CrystalDocs::DocsDocument,
  ) : CrystalDocs::TypeLinker
    CrystalDocs::TypeLinker.new(
      package_name: doc.package_name,
      version: doc_version.version,
      local_types: CrystalDocs::TypeLinker.local_names(document),
      dependency_index: CrystalDocs::DependencyIndex.for(doc.package_name, doc_version.version)
    )
  end
end
