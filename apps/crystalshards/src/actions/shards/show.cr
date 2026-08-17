class Shards::Show < BrowserAction
  include Shards::RendersShowPage

  # The registry addresses a shard by the repository it is, not by its name:
  # /shards/github.com/kemalcr/kemal.
  #
  # Three explicit segments rather than a glob. LuckyRouter registers a glob's
  # base path as well as the glob itself, so /shards/:host/*:rest would also
  # claim /shards/:host and collide with the legacy name route, which crashes
  # the app at boot with DuplicateRouteError. Explicit segments also keep
  # Shards::Show.with(...) working, which a glob route cannot generate.
  #
  # This URL is always the latest version. One named version lives at
  # /shards/:host/:owner/:repo/versions/:version, so the canonical address of a
  # shard never changes when a new release lands.
  get "/shards/:host/:owner/:repo" do
    shard = ShardQuery.new
      .preload_shard_versions
      .canonical_slug("#{host}/#{owner}/#{repo}")
      .first?

    if shard
      render_show_page(shard)
    elsif (legacy = ShardQuery.new.resolve_legacy_provider(host, owner, repo)) && (slug = legacy.canonical_slug)
      # The address the registry used before shards were addressed by host.
      # A permanent redirect rather than a render: the canonical address is
      # the one to hold, link and index, and 301 is what tells a crawler to
      # replace the one it has.
      redirect to: "/shards/#{slug}", status: 301
    else
      raise Lucky::RouteNotFoundError.new(context)
    end
  end
end
