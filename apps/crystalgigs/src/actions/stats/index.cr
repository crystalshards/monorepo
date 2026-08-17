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
    CrystalGigs::Stats.ensure_fresh

    # Pulls whatever Search Console owes us into search_console_daily before
    # the page reads it, claimed and bounded the same way. This call is the
    # only thing that ever invokes the fetcher: without it the service is
    # fully built, configured and granted, and never runs, and the section
    # sits on "waiting on the first fetch" forever while looking healthy.
    CrystalGigs::SearchConsole.refresh

    # Deliberately the listing and not `job`, which is where every individual
    # posting lands. This board charges employers to post, so a public list
    # of postings ranked by views is a public list of how each employer's
    # advert performed, and their competitors' too. Audience numbers are this
    # site's to publish. An employer's response rate is the employer's.
    #
    # Everything past a posting is `other` in the route map for the same
    # reason: the path from a posting to its payment is the board's funnel,
    # and a conversion rate is not an audience number.
    report = StatsReport.build(days, content_kinds: ["browse"])

    html Stats::IndexPage, report: report
  end
end
