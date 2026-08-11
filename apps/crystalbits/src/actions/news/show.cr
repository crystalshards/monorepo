class News::Show < BrowserAction
  # Scoped to approved, not merely filtered afterwards. A pending or rejected
  # item is a 404 here, so knowing a slug is not a way to read a draft.
  get "/news/:slug" do
    item = ContentItemQuery.new.publicly_visible.slug(slug).first?

    if item.nil?
      raise Lucky::RouteNotFoundError.new(context)
    elsif item.links_out_only?
      # Nothing of ours to show. Send the reader to the source rather than
      # holding them on a page that only restates someone else's headline.
      redirect to: item.source_url.to_s, status: 302
    else
      html News::ShowPage, item: item
    end
  end
end
