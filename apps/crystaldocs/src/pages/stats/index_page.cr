# The public stats page: what this site did, what people read, and where
# they came from, counted by the site itself.
#
# The design brief is honesty, and it shapes the markup:
#
#   * Nothing here is JavaScript. The chart is inline SVG drawn from the
#     same numbers the accompanying table carries, so the page is complete
#     with scripting off and the table is the chart's text equivalent.
#   * An absence is never rendered as a zero. A source that is not
#     configured says so; a period with no recordings says so; Google's
#     known lag is stated as a date rather than drawn as a dip.
#   * Every number is labelled with what it actually is. "Visitors" on a
#     per-day figure is an exact count of distinct people that day;
#     "visitors" on a per-page figure is that page's daily uniques added
#     across the period, and the column footnote says so, because a person
#     who read three pages would otherwise be three visitors.
class Stats::IndexPage < MainLayout
  needs report : StatsReport::Report

  # Chart geometry. viewBox only; the CSS makes the SVG fluid and the
  # numbers scale with it.
  CHART_WIDTH  = 720
  CHART_HEIGHT = 260
  PAD_LEFT     =  46 # y-axis labels
  PAD_RIGHT    =  10
  PAD_TOP      =  14
  PAD_BOTTOM   =  30 # x-axis labels

  def page_title
    "Site statistics"
  end

  def content
    section class: "section stats-page" do
      render_header
      render_period_picker
      render_activity
      render_most_read
      render_sources
      render_search_console
      render_reach
      render_methodology
    end
  end

  private def render_header
    div class: "page-header" do
      h1 do
        text "Site statistics"
      end
      para class: "stats-lede" do
        text "Everything on this page is counted by this site itself, on its " \
             "own servers, from the requests it serves. There are no cookies, " \
             "no tracking scripts, and no third parties in the loop."
      end
      render_coverage_note
    end
  end

  # The honest coverage line. Counting has a beginning, and the page says
  # when it was rather than letting a short history read as the whole story.
  private def render_coverage_note
    para class: "stats-coverage" do
      if first = @report.first_counted_day
        text "Counting since #{format_date(first)}"
        if through = @report.counted_through
          text " · numbers run through #{format_date(through)}"
        end
        text "."
        if @report.counting_error
          text " Counting is temporarily behind; the newest days are not settled yet."
        end
      elsif started = @report.recording_since
        # Rows are arriving and none has been rolled yet, which is every
        # site's first day. Saying "no visits recorded" here would be a
        # claim about the reader's own visit that this page just counted.
        text "Counting began #{format_date(started)}. A day's numbers are " \
             "rolled up once the day has ended, so the first of them appear " \
             "here tomorrow."
      else
        text "This site has not recorded any visits yet. When it does, they " \
             "will appear here, and this note will say when counting began."
      end
    end
  end

  # A server-rendered selector: each option is a link, the current one is
  # marked in both class and ARIA, and no option is a form control that
  # would need a script to submit.
  private def render_period_picker
    nav class: "period-picker", "aria-label": "Time period" do
      span class: "period-picker-label" do
        text "Showing"
      end
      StatsReport::PERIODS.each do |days|
        if days == @report.days
          tag "span", class: "period-option period-current", "aria-current": "true" do
            text period_label(days)
          end
        else
          a period_label(days), href: "/stats?period=#{days}", class: "period-option"
        end
      end
    end
  end

  private def period_label(days : Int32) : String
    "the last #{days} days"
  end

  private def render_activity
    section class: "stats-section" do
      div class: "section-head" do
        h2 do
          text "What the site did"
        end
        span class: "rule"
      end

      if @report.first_counted_day.nil? && @report.daily.all? { |d| d.views.zero? }
        # Never recorded anything: say so, in place of a flatlined chart
        # that would claim thirty quiet days.
        div class: "stats-empty" do
          para do
            text "No visits recorded in this period."
          end
        end
      else
        render_summary_strip
        render_chart
      end
    end
  end

  private def render_summary_strip
    dl class: "stats-summary" do
      div class: "stats-summary-item" do
        tag "dt" do
          text "Views"
        end
        tag "dd" do
          text format_number(@report.total_views)
        end
      end
      div class: "stats-summary-item" do
        tag "dt" do
          text "Visitors per day"
        end
        tag "dd" do
          text format_number(@report.average_daily_visitors.round.to_i64)
        end
      end
      if (busiest = @report.busiest_day) && busiest.views.positive?
        div class: "stats-summary-item" do
          tag "dt" do
            text "Busiest day"
          end
          tag "dd" do
            text format_number(busiest.views)
            span class: "stats-summary-note" do
              text " on #{format_date(busiest.day)}"
            end
          end
        end
      end
    end
  end

  # The chart, drawn as SVG from the same numbers the table below it
  # carries. Bars are views, the line is visitors. Everything painted comes
  # from the token set in app.css; this markup only carries geometry.
  private def render_chart
    daily = @report.daily
    max_value = daily.map { |d| Math.max(d.views, d.visitors) }.max
    ceiling = nice_ceiling(max_value)

    plot_width = CHART_WIDTH - PAD_LEFT - PAD_RIGHT
    plot_height = CHART_HEIGHT - PAD_TOP - PAD_BOTTOM
    count = daily.size
    slot = plot_width.to_f / count
    bar_width = {slot * 0.72, 1.0}.max

    x_for = ->(index : Int32) { PAD_LEFT + index * slot + (slot - bar_width) / 2 }
    y_for = ->(value : Int64) { PAD_TOP + plot_height - (value.to_f / ceiling) * plot_height }

    div class: "stats-chart" do
      tag "svg",
        "viewBox": "0 0 #{CHART_WIDTH} #{CHART_HEIGHT}",
        role: "img",
        "aria-labelledby": "stats-chart-title stats-chart-desc" do
        tag "title", id: "stats-chart-title" do
          text "Views and visitors per day, #{period_label(@report.days)}"
        end
        tag "desc", id: "stats-chart-desc" do
          text chart_description(daily)
        end

        # Mid and ceiling gridlines with their values; the baseline is the
        # axis itself. Three lines read cleanly where five would be noise.
        {0.5, 1.0}.each do |fraction|
          y = PAD_TOP + plot_height * (1 - fraction)
          empty_tag "line",
            x1: PAD_LEFT, y1: format_coord(y),
            x2: CHART_WIDTH - PAD_RIGHT, y2: format_coord(y),
            class: "chart-grid"
          tag "text",
            x: PAD_LEFT - 8, y: format_coord(y + 4),
            class: "chart-tick", "text-anchor": "end" do
            text format_number((ceiling * fraction).round.to_i64)
          end
        end
        empty_tag "line",
          x1: PAD_LEFT, y1: PAD_TOP + plot_height,
          x2: CHART_WIDTH - PAD_RIGHT, y2: PAD_TOP + plot_height,
          class: "chart-axis"

        # Date ticks: about six across the width, and always the last day.
        stride = {count // 6, 1}.max
        daily.each_with_index do |day, index|
          next unless index % stride == 0 || index == count - 1
          tag "text",
            x: format_coord(PAD_LEFT + index * slot + slot / 2),
            y: CHART_HEIGHT - 8,
            class: "chart-tick", "text-anchor": "middle" do
            text day.day.to_s("%-d %b")
          end
        end

        daily.each_with_index do |day, index|
          next if day.views.zero?
          empty_tag "rect",
            x: format_coord(x_for.call(index)),
            y: format_coord(y_for.call(day.views)),
            width: format_coord(bar_width),
            height: format_coord(PAD_TOP + plot_height - y_for.call(day.views)),
            class: "chart-bar"
        end

        points = daily.map_with_index do |day, index|
          "#{format_coord(PAD_LEFT + index * slot + slot / 2)},#{format_coord(y_for.call(day.visitors))}"
        end.join(" ")
        empty_tag "polyline", points: points, class: "chart-line"
      end

      para class: "chart-legend" do
        span class: "chart-swatch chart-swatch-bar" do
          text "views"
        end
        span class: "chart-swatch chart-swatch-line" do
          text "visitors"
        end
      end

      # The text equivalent. Native details/summary opens without a script,
      # so the numbers are reachable by keyboard and by screen reader alike.
      tag "details", class: "chart-data" do
        tag "summary" do
          text "Daily figures as a table"
        end
        tag "table" do
          tag "thead" do
            tag "tr" do
              tag "th", scope: "col" do
                text "Day"
              end
              tag "th", scope: "col", class: "num" do
                text "Views"
              end
              tag "th", scope: "col", class: "num" do
                text "Visitors"
              end
            end
          end
          tag "tbody" do
            daily.each do |day|
              tag "tr" do
                tag "td" do
                  text format_date(day.day)
                end
                tag "td", class: "num" do
                  text format_number(day.views)
                end
                tag "td", class: "num" do
                  text format_number(day.visitors)
                end
              end
            end
          end
        end
      end
    end
  end

  private def chart_description(daily : Array(StatsReport::DayCount)) : String
    total = daily.sum(0_i64, &.views)
    if busiest = daily.max_by?(&.views)
      "#{format_number(total)} views over #{daily.size} days, " \
      "peaking at #{format_number(busiest.views)} on #{format_date(busiest.day)}. " \
      "The full figures follow as a table."
    else
      "#{format_number(total)} views over #{daily.size} days. The full figures follow as a table."
    end
  end

  private def render_most_read
    section class: "stats-section" do
      div class: "section-head" do
        h2 do
          text "What people read"
        end
        span class: "rule"
      end

      if @report.top_pages.empty?
        div class: "stats-empty" do
          para do
            text "Nothing read in this period."
          end
        end
      else
        tag "table", class: "stats-table" do
          tag "thead" do
            tag "tr" do
              tag "th", scope: "col" do
                text "Package"
              end
              tag "th", scope: "col", class: "num" do
                text "Views"
              end
              tag "th", scope: "col", class: "num" do
                text "Visitors"
                tag "span", class: "visually-hidden" do
                  text ", daily uniques added across the period"
                end
              end
            end
          end
          tag "tbody" do
            @report.top_pages.each do |page|
              tag "tr" do
                tag "td" do
                  a page_label(page.path), href: page.path
                end
                tag "td", class: "num" do
                  text format_number(page.views)
                end
                tag "td", class: "num" do
                  text format_number(page.visitors)
                end
              end
            end
          end
        end
        para class: "stats-footnote" do
          text "Visitors on a single page are that page's daily unique " \
               "visitors added across the period: a reader who came every " \
               "day counts once per day, and a reader of three pages counts " \
               "once on each. Only per-day figures count people exactly."
        end
      end
    end
  end

  private def render_sources
    section class: "stats-section" do
      div class: "section-head" do
        h2 do
          text "Where they came from"
        end
        span class: "rule"
      end

      render_direct_share

      if @report.referrers.empty?
        div class: "stats-empty" do
          para do
            if @report.direct_views.positive?
              text "No referring sites in this period: every recorded view " \
                   "arrived directly."
            else
              text "No visits recorded in this period."
            end
          end
        end
      else
        tag "table", class: "stats-table" do
          tag "thead" do
            tag "tr" do
              tag "th", scope: "col" do
                text "Referring site"
              end
              tag "th", scope: "col", class: "num" do
                text "Views"
              end
              tag "th", scope: "col", class: "num" do
                text "Visitors"
              end
            end
          end
          tag "tbody" do
            @report.referrers.each do |referrer|
              tag "tr" do
                tag "td", class: "mono" do
                  text referrer.host
                end
                tag "td", class: "num" do
                  text format_number(referrer.views)
                end
                tag "td", class: "num" do
                  text format_number(referrer.visitors)
                end
              end
            end
          end
        end
      end
    end
  end

  # Direct is the absence of a referrer, so it is stated as a share rather
  # than ranked as if it were a source.
  private def render_direct_share
    total = @report.total_views
    return if total.zero?

    share = (@report.direct_views.to_f / total * 100).round.to_i
    para class: "stats-direct" do
      text "#{share}% of views arrived directly: typed in, bookmarked, or " \
           "from a source that sends no referrer."
    end
  end

  # Google's half of the picture, always labelled as theirs. The states, in
  # order: not configured, a failed fetch, waiting on the first fetch, no
  # queries in the period, and data. Only the last renders numbers; the rest
  # say what is true.
  private def render_search_console
    gsc = @report.search_console

    section class: "stats-section" do
      div class: "section-head" do
        h2 do
          text "What people searched for"
        end
        span class: "rule"
      end

      unless gsc.configured
        div class: "stats-empty" do
          para do
            text "This site is not linked to Google Search Console, so there " \
                 "are no search numbers to show."
          end
        end
        return
      end

      para class: "stats-attribution" do
        text "From Google Search Console: Google's own numbers, reported as " \
             "Google counts them"
        if through = gsc.covered_through
          text ", currently through #{format_date(through)}"
        end
        text "."
      end

      if gsc.last_error
        div class: "stats-empty" do
          para do
            text "The latest fetch from Google failed."
            if through = gsc.covered_through
              text " Figures through #{format_date(through)} remain shown below."
            else
              text " No figures have been fetched yet."
            end
          end
        end
      end

      if gsc.queries.empty?
        unless gsc.last_error
          div class: "stats-empty" do
            para do
              if gsc.covered_through.nil?
                text "Waiting on the first fetch from Google. Search Console " \
                     "figures typically lag two to three days, so recent days " \
                     "never appear here right away."
              else
                text "Google reports no search queries for this site in this period."
              end
            end
          end
        end
      else
        tag "table", class: "stats-table" do
          tag "thead" do
            tag "tr" do
              tag "th", scope: "col" do
                text "Query"
              end
              tag "th", scope: "col", class: "num" do
                text "Clicks"
              end
              tag "th", scope: "col", class: "num" do
                text "Impressions"
              end
              tag "th", scope: "col", class: "num" do
                text "Avg. position"
              end
            end
          end
          tag "tbody" do
            gsc.queries.each do |query|
              tag "tr" do
                tag "td" do
                  text query.query
                end
                tag "td", class: "num" do
                  text format_number(query.clicks)
                end
                tag "td", class: "num" do
                  text format_number(query.impressions)
                end
                tag "td", class: "num" do
                  text query.position.round(1).to_s
                end
              end
            end
          end
        end
        para class: "stats-footnote" do
          text "Position is the average place this site appeared in Google's " \
               "results for that query, weighted by impressions. Google " \
               "revises its most recent days, so they appear here only once " \
               "settled."
        end
      end
    end
  end

  private def render_reach
    section class: "stats-section" do
      div class: "section-head" do
        h2 do
          text "Reach"
        end
        span class: "rule"
      end

      if @report.countries.empty?
        div class: "stats-empty" do
          para do
            text "No visits recorded in this period."
          end
        end
      else
        tag "ol", class: "country-list" do
          @report.countries.each do |country|
            tag "li" do
              span class: "country-code mono" do
                text country_label(country.code)
              end
              span class: "country-views num" do
                text format_number(country.views)
              end
            end
          end
        end
        para class: "stats-footnote" do
          text "Countries come from the load balancer's geo header, by views. " \
               "\"Unknown\" is traffic the header did not resolve, shown " \
               "rather than dropped."
        end
      end
    end
  end

  # The methodology, in small print, because this page exists so a reader
  # never has to wonder how the numbers were made.
  private def render_methodology
    para class: "stats-methodology" do
      text "How this is counted: each request this site serves is logged with " \
           "its path, the referring site's host, and the country from the " \
           "load balancer's geo header. A per-day hash of the visitor's " \
           "address and browser counts distinct people without recording " \
           "anyone's address, and it rotates daily, so nothing follows a " \
           "reader from one day to the next. Known bots and failed responses " \
           "are never counted. Raw requests are pruned after thirty days; " \
           "the daily figures above are what remains."
    end
  end

  # The display name for a registry path: the shard's name is the last path
  # segment, and the link stays the verbatim request path.
  private def page_label(path : String) : String
    path.sub(/\A\/shards\//, "").presence || path
  end

  private def country_label(code : String) : String
    code == "unknown" ? "Unknown" : code.upcase
  end

  private def format_date(day : Time) : String
    day.to_s("%b %-d, %Y")
  end

  private def format_number(number : Int64) : String
    number.to_s.reverse.gsub(/(\d{3})(?=\d)/, "\\1,").reverse
  end

  # Coordinates are rounded to two decimals: exact enough at any render
  # size, and shorter than the full float expansion.
  private def format_coord(value : Float64) : String
    value.round(2).to_s
  end

  private def format_coord(value : Int32) : String
    value.to_s
  end

  # The top of the y-axis, rounded up to a 1/2/2.5/5 x 10^k step so the
  # mid-gridline always lands on a number a person would write down.
  private def nice_ceiling(max_value : Int64) : Float64
    return 10.0 if max_value <= 10

    magnitude = 10.0 ** Math.log10(max_value).floor
    {1.0, 2.0, 2.5, 5.0, 10.0}.each do |step|
      candidate = magnitude * step
      return candidate if candidate >= max_value
    end
    magnitude * 10.0
  end
end
