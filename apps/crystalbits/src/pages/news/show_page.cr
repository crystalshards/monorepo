class News::ShowPage < MainLayout
  needs item : ContentItem

  def page_title
    @item.title
  end

  def content
    article class: "content-detail" do
      render_header
      render_machine_notice if @item.machine_drafted
      render_body
      mount ContentProvenance, item: @item, detailed: true
    end
  end

  private def render_header
    header class: "content-detail-header" do
      h1 class: "content-detail-title" do
        text @item.title
      end

      if summary = @item.summary.presence
        para class: "content-detail-summary" do
          text summary
        end
      end
    end
  end

  # Stated before the text, not after it. A reader should know what they are
  # about to read before they read it, not discover it in a footer.
  private def render_machine_notice
    aside class: "machine-notice", role: "note" do
      tag "i", class: "fa-solid fa-robot", "aria-hidden": "true"

      div do
        strong "Machine-drafted"
        para do
          text "CrystalBits wrote this summary from the public discussions listed " \
               "below, then an editor reviewed it before publication. It is our " \
               "own wording, not anybody else's text."
        end
      end
    end
  end

  private def render_body
    div class: "content-detail-body" do
      # The only `raw` on this page, and its argument has been through
      # BitsHtml: Markd in safe mode, then the allowlist sanitiser.
      raw BitsHtml.markdown(@item.body.to_s)
    end
  end
end
