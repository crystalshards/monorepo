class Docs::Show < BrowserAction
  get "/docs/:package_name" do
    doc = DocQuery.new
      .preload_versions
      .package_name(package_name)
      .first?

    if doc.nil?
      raise Lucky::RouteNotFoundError.new(context)
    end

    if current_version = doc.current_version
      redirect to: "/docs/#{package_name}/#{current_version}"
    else
      html Docs::ShowPage, doc: doc
    end
  end
end
