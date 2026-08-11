class Admin::Moderation::Index < BrowserAction
  include Auth::RequireEditor

  param state : String?

  get "/admin/moderation" do
    selected = state.presence.try { |value| ContentItem::State::ALL.includes?(value) ? value : nil }

    query = ContentItemQuery.new
    items = if selected
              query.state(selected).oldest_first.to_a
            else
              query.pending_review.oldest_first.to_a
            end

    html Admin::Moderation::IndexPage,
      items: items,
      state: selected,
      pending_count: ContentItemQuery.new.pending_review.select_count,
      generator_configured: DraftGenerator.configured?,
      generator_missing: DraftGenerator.missing_configuration
  end
end
