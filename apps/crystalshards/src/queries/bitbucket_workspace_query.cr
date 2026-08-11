class BitbucketWorkspaceQuery < BitbucketWorkspace::BaseQuery
  def for_slug(value : String) : BitbucketWorkspace?
    clone.slug(value).first?
  end

  # The workspaces a sweep will walk, in the order it walks them.
  #
  # Sorted by slug so the order is the same on every run. That is what makes the
  # cursor meaningful: it names a slug and a page, and resuming means finding
  # that slug's place in this list again. An unordered list would resume in a
  # different position each time and silently skip workspaces.
  def enumerable : Array(BitbucketWorkspace)
    clone.enabled(true).slug.asc_order.results
  end
end
