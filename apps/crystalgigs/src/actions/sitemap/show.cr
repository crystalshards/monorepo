# Lists every currently live posting so Google (and any other crawler) can
# discover and re-check them without waiting on an on-site link to each one -
# the jobs list only shows one page of results at a time and never links
# forward past its own pagination. `JobQuery#open_only` is the same
# definition of "live" the jobs list itself, the ad feed, and Google's own
# structured data all already use, so a posting that stops advertising as
# open (see Jobs::Show) drops out of the next sitemap fetch the same way it
# drops out of every other list on the board.
#
# Origin comes from `Lucky::RouteHelper.settings.base_uri`
# (`config/route_helper.cr`), which is this app's own `APP_DOMAIN` -
# terraform's `var.app_domains["crystalgigs"]`, wired through
# `local.sites` - required in production and never a literal here.
class Sitemap::Show < BrowserAction
  get "/sitemap.xml" do
    origin = Lucky::RouteHelper.settings.base_uri
    jobs = JobQuery.new.open_only.results

    xml = String.build do |io|
      io << %(<?xml version="1.0" encoding="UTF-8"?>\n)
      io << %(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n)

      jobs.each do |job|
        io << "  <url>\n"
        io << "    <loc>" << origin << Jobs::Show.with(job_id: job.id).path << "</loc>\n"
        io << "    <lastmod>" << job.updated_at.to_rfc3339 << "</lastmod>\n"
        io << "  </url>\n"
      end

      io << "</urlset>\n"
    end

    plain_text xml
  end
end
