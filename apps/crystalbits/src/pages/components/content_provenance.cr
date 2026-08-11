# Where an item came from, shown wherever the item is shown.
#
# Provenance is not a footnote. A reader should be able to tell, without
# clicking, whether they are reading somebody's contribution, a pointer to the
# Crystal blog, or something we drafted by machine, and under what terms.
class ContentProvenance < Lucky::BaseComponent
  needs item : ContentItem
  needs detailed : Bool = false

  def render
    div class: "provenance" do
      render_origin_badge
      render_attribution
      render_source_link
      render_sources if @detailed && @item.source_urls.size > 1
      render_license if @detailed && @item.license_note
    end
  end

  private def render_origin_badge
    span class: "provenance-badge #{badge_modifier}" do
      tag "i", class: badge_icon, "aria-hidden": "true"
      text " "
      text @item.origin_label
    end
  end

  # The machine-drafted label is the loudest thing on the card by design.
  # Readers are owed an unambiguous answer to "did a person write this".
  private def badge_modifier : String
    case @item.origin
    when ContentItem::Origin::GENERATED    then "provenance-badge-machine"
    when ContentItem::Origin::CRYSTAL_BLOG then "provenance-badge-upstream"
    else                                        "provenance-badge-human"
    end
  end

  private def badge_icon : String
    case @item.origin
    when ContentItem::Origin::GENERATED    then "fa-solid fa-robot"
    when ContentItem::Origin::CRYSTAL_BLOG then "fa-solid fa-rss"
    else                                        "fa-solid fa-user-pen"
    end
  end

  private def render_attribution
    para class: "provenance-attribution" do
      text @item.attribution
    end

    if date = @item.original_published_at
      para class: "provenance-date" do
        text "Originally published #{date.to_s("%B %-d, %Y")}"
      end
    end
  end

  private def render_source_link
    return unless url = display_url

    para class: "provenance-source" do
      text "Source: "
      a href: url, rel: "noopener nofollow", target: "_blank" do
        text short_url(url)
      end
    end
  end

  # Contributions show the author's canonical link if they gave one. Everything
  # else shows the URL it was ingested from.
  private def display_url : String?
    if @item.contribution?
      @item.canonical_url.presence
    else
      @item.source_url.presence
    end
  end

  private def render_sources
    div class: "provenance-sources" do
      para class: "provenance-sources-label" do
        text "Written from these discussions:"
      end

      ul do
        @item.source_urls.each do |url|
          li do
            a href: url, rel: "noopener nofollow", target: "_blank" do
              text short_url(url)
            end
          end
        end
      end
    end
  end

  private def render_license
    para class: "provenance-license" do
      text @item.license_note.to_s
    end
  end

  private def short_url(url : String) : String
    uri = URI.parse(url) rescue nil
    return url unless uri && (host = uri.host)

    path = uri.path
    path = path.rchop('/') if path.size > 1
    display = "#{host}#{path}"
    display.size > 72 ? display[0, 69] + "..." : display
  end
end
