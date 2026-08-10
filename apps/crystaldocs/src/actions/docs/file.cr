class Docs::File < BrowserAction
  # Serves the stored documentation files themselves, at their own paths.
  #
  # Generated Crystal documentation is a tree of whole HTML documents that
  # link to each other with relative paths, so it has to be served as itself
  # rather than embedded in our layout: wrapping it would nest one document
  # inside another and break every relative link in it. Before this route no
  # URL reached any file below a version, so a stored doc set could be
  # browsed only through the ?file= param on the version page, one file at a
  # time, with none of its own links working.
  #
  # The route is split into a first segment and a glob rather than one glob
  # for two reasons, both forced by LuckyRouter:
  #
  #   1. A glob also registers its own base path, so a plain
  #      /docs/:package_name/:version/*:path would claim
  #      /docs/:package_name/:version and collide with Docs::Version.
  #   2. Route helpers cannot generate a path for a glob route. Keeping the
  #      glob off Docs::Version leaves its Docs::Version.with(...) helper
  #      working for every page and spec that links to a version.
  #
  # The two segments are rejoined below, so URLs stay the natural shape:
  #   /docs/kemal/1.4.0/index.html
  #   /docs/kemal/1.4.0/api/index.html
  get "/docs/:package_name/:version/:top_level/*:rest" do
    doc = DocQuery.new
      .preload_doc_versions
      .package_name(package_name)
      .first?

    if doc.nil?
      raise Lucky::RouteNotFoundError.new(context)
    end

    doc_version = doc.doc_versions.find { |v| v.version == version }

    if doc_version.nil?
      redirect_to_current_version(doc)
    else
      serve(doc_version)
    end
  end

  # The version segment does not name a version of this package. The usual
  # cause is a deep link written without one, for example
  # /docs/kemal/api/index.html, so treat the whole tail as a path under the
  # current version rather than dead-ending on a URL that is one segment
  # away from correct.
  private def redirect_to_current_version(doc : Doc)
    current = doc.current_version

    if current && current != version
      redirect to: "/docs/#{package_name}/#{current}/#{version}/#{requested_path}"
    else
      raise Lucky::RouteNotFoundError.new(context)
    end
  end

  private def serve(doc_version : DocVersion)
    path = safe_path(requested_path)

    if path.nil?
      raise Lucky::RouteNotFoundError.new(context)
    end

    fetch = CrystalDocs::DocsStorageService.new.fetch_doc_file(
      package_name: package_name,
      version: doc_version.version,
      file_path: path
    )

    if body = fetch.content
      send_text_response(body, content_type_for(path))
    elsif fetch.store_answered?
      # Storage answered and the object is not there.
      raise Lucky::RouteNotFoundError.new(context)
    else
      # Storage could not be reached. That is our failure, not a missing
      # page, so do not tell the reader the documentation does not exist.
      send_text_response(
        "Documentation storage is temporarily unavailable. Please try again.",
        "text/plain; charset=utf-8",
        503
      )
    end
  end

  # The router hands back the first segment and the remainder separately.
  private def requested_path : String
    tail = rest

    if tail && !tail.empty?
      "#{top_level}/#{tail}"
    else
      top_level
    end
  end

  # This path is appended to an object key, so a traversal segment could
  # reach another package's documentation. Only plain relative paths pass.
  private def safe_path(path : String) : String?
    cleaned = path.strip.lchop('/')

    return nil if cleaned.empty?
    return nil if cleaned.includes?("..")
    return nil if cleaned.includes?("//")
    return nil if cleaned.starts_with?('.')

    # A directory request serves that directory's index.
    cleaned = "#{cleaned}index.html" if cleaned.ends_with?('/')
    cleaned
  end

  private def content_type_for(path : String) : String
    case ::File.extname(path).downcase
    when ".html", ".htm" then "text/html; charset=utf-8"
    when ".css"          then "text/css; charset=utf-8"
    when ".js"           then "application/javascript; charset=utf-8"
    when ".json"         then "application/json; charset=utf-8"
    when ".svg"          then "image/svg+xml"
    when ".png"          then "image/png"
    when ".jpg", ".jpeg" then "image/jpeg"
    when ".woff2"        then "font/woff2"
    when ".woff"         then "font/woff"
    when ".txt", ".md"   then "text/plain; charset=utf-8"
    else                      "application/octet-stream"
    end
  end
end
