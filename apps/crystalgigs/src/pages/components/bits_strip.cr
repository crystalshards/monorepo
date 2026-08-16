require "../../services/bits_feed"

# The CrystalBits strip on the home page: the most recent articles from our
# sister site, each card linking off to it.
#
# Whether there is anything to show at all belongs to
# CrystalGigs::BitsFeed: a feed that answered with nothing renders nothing,
# and a feed that could not be reached renders nothing. There is no fallback
# card and no heading over an empty space, because an empty strip would read
# as CrystalBits having nothing to say, which a failed fetch has not
# established.
class BitsStrip < Lucky::BaseComponent
  needs limit : Int32 = 3

  def render
    origin = CrystalGigs::BitsFeed.origin
    return unless origin

    articles = CrystalGigs::BitsFeed.current(limit)
    return if articles.empty?

    # A named <aside> is a complementary landmark, so the strip is listed
    # among the page's regions and can be jumped to or skipped. The name
    # names CrystalBits, so it is clear whose articles these are and that
    # following one leaves this site.
    tag "aside",
      class: "bits-strip",
      "aria-label": "From CrystalBits, our sister site" do
      div class: "bits-strip-head" do
        para class: "bits-strip-source" do
          tag "i", class: "fa-solid fa-newspaper bits-strip-icon", "aria-hidden": "true"
          text "From our sister site"
        end
        h2 class: "bits-strip-heading" do
          text "The latest from CrystalBits"
        end
      end

      # No "see all" link. Every article title already goes to CrystalBits,
      # and the masthead and footer carry the standing cross-site links.
      ul class: "bits-strip-list" do
        articles.each { |article| render_article(article, origin) }
      end
    end
  end

  private def render_article(article : CrystalGigs::BitsFeed::Article, origin : String)
    li class: "bits-strip-item" do
      # The title is the link, so the link's accessible name is the article
      # title rather than the whole card. One tab stop per article.
      a article.title,
        href: CrystalGigs::BitsFeed.article_url(origin, article),
        class: "bits-strip-title",
        rel: "noopener"

      unless (excerpt = article.excerpt).nil? || excerpt.blank?
        para class: "bits-strip-excerpt" do
          text excerpt
        end
      end
    end
  end
end
