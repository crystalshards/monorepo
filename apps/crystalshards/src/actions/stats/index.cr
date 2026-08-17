class Stats::Index < BrowserAction
  # Declared rather than read straight off params: the page builds its own
  # period links with Stats::Index.with(period: ...), and Lucky only accepts
  # a query parameter in a route helper when the action names it.
  param period : String?

  # Public by design: the same numbers an owner would screenshot out of a
  # commercial analytics product, rendered by the site itself, with nothing
  # behind a login. There is no JavaScript on this page; the chart is SVG
  # drawn from the same numbers the table under it carries.
  get "/stats" do
    days = StatsReport.period_days(params.get?(:period))

    # Rolls yesterday and anything older still pending into daily_stats
    # before the page reads it. Claimed and bounded inside the service, so a
    # second reader arriving mid-pass renders what is already rolled rather
    # than waiting, and a page load can never hang on it. Without this call
    # the table only ever fills by accident and the page reports "not
    # recording yet" forever while raw rows pile up behind it.
    Stats.ensure_fresh

    # The registry's read surface is packages, so that is the list this
    # page leads with. The kinds come from the collector's route map;
    # anything it stops classifying as a package simply stops appearing here.
    report = StatsReport.build(days, content_kinds: ["package"])

    html Stats::IndexPage, report: report
  end
end
