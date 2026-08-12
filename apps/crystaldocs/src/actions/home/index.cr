class Home::Index < BrowserAction
  get "/" do
    # How many shards exist is the registry's answer, and it is the same
    # `count(*)` crystalshards reports. Reading it from this app's own `docs`
    # table counted the packages somebody had opened here, which is why the
    # two sites showed different numbers for the same ecosystem.
    #
    # Nil when the registry cannot be reached, and the page then prints no
    # figure at all rather than this app's much smaller one.
    total_packages = CrystalDocs::RegistryPackages.build.total_packages

    # Local, and deliberately so. This counts versions this site has actually
    # built, which is build state and is exactly what `doc_versions` is for.
    # It is labelled as such on the page: it is not a count of published
    # releases and must not read as one.
    built_versions = DocVersionQuery.new.build_status("success").select_count

    # No `preload_doc_versions`: the card reads build state from
    # `PackageCatalogue`, which aggregates it for the whole section in one
    # query. Preloading here loaded every version row of every card to answer
    # a question nothing on this page asks any more.
    recent_docs = DocQuery.new
      .last_updated_at.desc_order
      .limit(6)

    popular_docs = DocQuery.new
      .total_views.desc_order
      .limit(6)

    html Home::IndexPage,
      total_packages: total_packages,
      built_versions: built_versions,
      recent_entries: CrystalDocs::PackageCatalogue.for_docs(recent_docs),
      popular_entries: CrystalDocs::PackageCatalogue.for_docs(popular_docs)
  end
end
