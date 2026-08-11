class Admin::Moderation::IndexPage < MainLayout
  needs items : Array(ContentItem)
  needs state : String?
  needs pending_count : Int64
  needs generator_configured : Bool
  needs generator_missing : Array(String)

  TABS = [
    {nil, "Awaiting review"},
    {ContentItem::State::APPROVED, "Approved"},
    {ContentItem::State::REJECTED, "Rejected"},
  ]

  def page_title
    "Moderation queue"
  end

  def content
    section class: "moderation" do
      render_header
      render_generator_status
      render_tabs
      render_queue
    end
  end

  private def render_header
    div class: "moderation-header" do
      h1 "Moderation queue"

      para class: "moderation-lede" do
        text "#{@pending_count} item#{@pending_count == 1 ? "" : "s"} awaiting review. " \
             "Nothing on this page is public until you approve it, whichever source it came from."
      end
    end
  end

  # The generator's configuration state is shown here rather than hidden in a
  # log, because "no machine drafts appeared" and "machine drafting is turned
  # off" look identical from the queue otherwise.
  private def render_generator_status
    div class: @generator_configured ? "moderation-status" : "moderation-status moderation-status-off" do
      tag "i", class: @generator_configured ? "fa-solid fa-robot" : "fa-solid fa-plug-circle-xmark", "aria-hidden": "true"

      if @generator_configured
        para do
          text " Machine drafting is configured. Run "
          code "lucky bits.generate_drafts"
          text " to add drafts from community discussion."
        end
      else
        para do
          text " Machine drafting is off: "
          text @generator_missing.join(" and ")
          text " not set. Nothing is generated and nothing is faked."
        end
      end
    end
  end

  private def render_tabs
    nav class: "moderation-tabs", "aria-label": "Filter by state" do
      TABS.each do |value, label|
        current = value == @state

        a href: value ? "/admin/moderation?state=#{value}" : "/admin/moderation",
          class: current ? "moderation-tab moderation-tab-current" : "moderation-tab",
          "aria-current": current ? "page" : "false" do
          text label
        end
      end
    end
  end

  private def render_queue
    if @items.empty?
      para class: "moderation-empty" do
        text "Nothing here."
      end
    else
      div class: "moderation-list" do
        @items.each { |item| render_row(item) }
      end
    end
  end

  private def render_row(item : ContentItem)
    article class: "moderation-item" do
      div class: "moderation-item-head" do
        h2 class: "moderation-item-title" do
          text item.title
        end

        span class: "moderation-state moderation-state-#{item.state}" do
          text item.state
        end
      end

      mount ContentProvenance, item: item, detailed: true

      if contact = item.submitter_contact.presence
        para class: "moderation-contact" do
          tag "i", class: "fa-solid fa-envelope", "aria-hidden": "true"
          text " Reply to: #{contact}"
        end
      end

      render_preview(item)
      render_decisions(item)
    end
  end

  # The reviewer sees the body as a reader would, which means through the same
  # sanitiser. Reviewing raw submitted markup in an admin page is how an XSS
  # lands on the person with approval rights.
  private def render_preview(item : ContentItem)
    if body = item.body.presence
      details class: "moderation-preview" do
        summary "Read the submission"
        div class: "content-detail-body" do
          raw BitsHtml.markdown(body)
        end
      end
    elsif summary_text = item.summary.presence
      para class: "moderation-summary" do
        text summary_text
      end
    end
  end

  private def render_decisions(item : ContentItem)
    div class: "moderation-actions" do
      if item.state != ContentItem::State::APPROVED
        decision_form item, ContentItem::State::APPROVED, "Approve and publish", "btn-primary"
      end

      if item.state != ContentItem::State::REJECTED
        decision_form item, ContentItem::State::REJECTED, "Reject", "btn-secondary"
      end
    end
  end

  private def decision_form(item : ContentItem, decision : String, label : String, button_class : String)
    form_for Admin::Moderation::Update.with(content_item_id: item.id.to_s), class: "moderation-decision" do
      tag "input", type: "hidden", name: "decision", value: decision
      button type: "submit", class: button_class do
        text label
      end
    end
  end
end
