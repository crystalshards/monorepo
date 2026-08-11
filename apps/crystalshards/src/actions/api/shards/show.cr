class Api::Shards::Show < ApiAction
  include Api::Auth::SkipRequireAuthToken

  get "/api/shards/:host/:owner/:repo" do
    shard = ShardQuery.new
      .preload_shard_versions
      .canonical_slug("#{host}/#{owner}/#{repo}")
      .first?

    if shard.nil?
      head 404
    else
      json ShardPayload.detail(shard)
    end
  end
end
