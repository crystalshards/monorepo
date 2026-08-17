class Stats::Index < BrowserAction
  # Public by design: the same numbers an owner would screenshot out of a
  # commercial analytics product, rendered by the site itself, with nothing
  # behind a login. There is no JavaScript on this page; the chart is SVG
  # drawn from the same numbers the table under it carries.
  get "/stats" do
    days = StatsReport.period_days(params.get?(:period))

    # INTEGRATION SEAM: the rollup service (stats/rollups branch) ships a
    # `Stats.ensure_fresh` that lazily claims and rolls pending raw rows on
    # read. Call it here, first, once both branches are integrated: without
    # it this page reads daily_stats exactly as it stands and renders its
    # honest "not recording yet" state when the table is empty.
    #
    # The registry's read surface is packages, so that is the list this
    # page leads with. The kinds come from the collector's route map;
    # anything it stops classifying as a package simply stops appearing here.
    report = StatsReport.build(days, content_kinds: ["package"])

    html Stats::IndexPage, report: report
  end
end
