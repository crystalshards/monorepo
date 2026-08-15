# Nothing on this board needs to be kept out of a crawler - there is no
# admin surface and no private area under this app - so this allows
# everything and only exists to point at the sitemap. Without this file at
# all, a crawler still indexes the board fine (a missing robots.txt means
# "crawl everything" by convention), but Google's own sitemap guidance is to
# publish one, and a `Sitemap:` line here is how a crawler finds it without
# having to be told the URL out of band.
class Robots::Show < BrowserAction
  get "/robots.txt" do
    origin = Lucky::RouteHelper.settings.base_uri

    body = <<-ROBOTS
      User-agent: *
      Allow: /

      Sitemap: #{origin}/sitemap.xml
      ROBOTS

    plain_text body
  end
end
