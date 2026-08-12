class Docs::Show < BrowserAction
  include Docs::BareNameResolution

  get "/docs/:package_name" do
    doc = DocQuery.new
      .preload_doc_versions
      .package_name(package_name)
      .first?

    response = resolve_bare_name(package_name, !doc.nil?) do |slug|
      CrystalDocs::PackagePaths.package_path(slug)
    end

    if response
      response
    elsif doc
      redirect_to_current(doc)
    else
      raise Lucky::RouteNotFoundError.new(context)
    end
  end

  private def redirect_to_current(doc : Doc)
    if current_version = doc.current_version
      redirect to: CrystalDocs::PackagePaths.version_path(doc.package_name, current_version)
    else
      html Docs::ShowPage, doc: doc
    end
  end
end
