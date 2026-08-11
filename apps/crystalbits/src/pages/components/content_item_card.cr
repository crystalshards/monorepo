class ContentItemCard < Lucky::BaseComponent
  needs item : ContentItem
  needs heading_level : Int32 = 2

  def render
    article class: "content-card #{origin_modifier}" do
      tag "h#{@heading_level}", class: "content-card-title" do
        render_title_link
      end

      if summary = @item.summary.presence
        para class: "content-card-summary" do
          text summary
        end
      end

      mount ContentProvenance, item: @item
    end
  end

  # Feed items send the reader off-site, so the link is marked as leaving
  # rather than pretending the article lives here.
  private def render_title_link
    if @item.links_out_only?
      a href: @item.read_url, rel: "noopener", target: "_blank" do
        text @item.title
        text " "
        tag "i", class: "fa-solid fa-arrow-up-right-from-square content-card-external", "aria-hidden": "true"
        span class: "visually-hidden" do
          text "(opens on crystal-lang.org)"
        end
      end
    else
      a href: @item.read_url do
        text @item.title
      end
    end
  end

  private def origin_modifier : String
    "content-card-#{@item.origin.gsub('_', '-')}"
  end
end
