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
    CrystalDocs::Stats.ensure_fresh

    # Pulls whatever Search Console owes us into search_console_daily before
    # the page reads it, claimed and bounded the same way. This call is the
    # only thing that ever invokes the fetcher: without it the service is
    # fully built, configured and granted, and never runs, and the section
    # sits on "waiting on the first fetch" forever while looking healthy.
    CrystalDocs::SearchConsole.refresh

    # All three documentation kinds, in one list, because this site's read
    # surface is not a single page per package: a reader lands on a package,
    # opens a version, then reads types under it. Leading with `package`
    # alone would rank the doorways and hide the rooms, which is the
    # opposite of what this page is for.
    report = StatsReport.build(
      days,
      content_kinds: ["package", "docs_version", "docs_type"]
    )

    html Stats::IndexPage, report: report
  end
end
