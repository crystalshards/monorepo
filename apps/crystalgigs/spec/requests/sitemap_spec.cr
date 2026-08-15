require "../spec_helper"

describe Sitemap::Show do
  it "lists a live posting with its last modified time and excludes everything that is not live" do
    live = JobFactory.create &.title("Live Posting")
      .published_at(Time.utc).expires_at(Time.utc + 10.days).active(true)
    draft = JobFactory.create &.title("Draft Posting").published_at(nil)
    expired = JobFactory.create &.title("Expired Posting")
      .published_at(Time.utc - 40.days).expires_at(Time.utc - 1.day).active(true)
    delisted = JobFactory.create &.title("Delisted Posting")
      .published_at(Time.utc).active(false)

    response = BrowserClient.exec(Sitemap::Show)

    response.status_code.should eq(200)

    origin = Lucky::RouteHelper.settings.base_uri
    response.body.should contain("<loc>#{origin}/jobs/#{live.id}</loc>")
    response.body.should contain("<lastmod>#{live.updated_at.to_rfc3339}</lastmod>")

    response.body.should_not contain("/jobs/#{draft.id}<")
    response.body.should_not contain("/jobs/#{expired.id}<")
    response.body.should_not contain("/jobs/#{delisted.id}<")
  end

  it "renders a well-formed urlset even with no live postings" do
    response = BrowserClient.exec(Sitemap::Show)

    response.status_code.should eq(200)
    response.body.should contain(%(<?xml version="1.0" encoding="UTF-8"?>))
    response.body.should contain(%(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">))
    response.body.should contain("</urlset>")
  end
end
