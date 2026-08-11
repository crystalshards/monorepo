class News::Index < BrowserAction
  param origin : String?

  # The public index. It reads approved rows and nothing else, so a feed
  # outage, a stalled generator or an empty review queue all render the same
  # way: whatever an editor has already approved.
  get "/news" do
    query = ContentItemQuery.new.publicly_visible

    selected = origin.presence.try { |value| ContentItem::Origin::ALL.includes?(value) ? value : nil }
    query = query.origin(selected) if selected

    html News::IndexPage,
      items: query.newest_first.limit(50).to_a,
      origin: selected
  end
end
