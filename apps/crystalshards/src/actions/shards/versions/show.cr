# One named version of one shard.
#
#   /shards/github.com/kemalcr/kemal/versions/1.12.0
#
# The same page as Shards::Show, showing the manifest, dependencies and tag
# date of the version named in the path rather than of the newest one. The
# unversioned URL stays the canonical address of the shard and always means
# "latest", so a link to a shard does not go stale when a release lands, and a
# link to a release does not silently start describing a different one.
#
# A version this shard has never published is a 404 rather than an empty page.
# The whole point of this work is that a URL either has content behind it or
# says clearly that it does not, and "here is a shard, at a version that does
# not exist" is neither.
class Shards::Versions::Show < BrowserAction
  include Shards::RendersShowPage

  get "/shards/:host/:owner/:repo/versions/:version" do
    shard = ShardQuery.new
      .preload_shard_versions
      .canonical_slug("#{host}/#{owner}/#{repo}")
      .first?

    if shard.nil?
      raise Lucky::RouteNotFoundError.new(context)
    end

    render_show_page(shard, requested_version: version)
  end
end
