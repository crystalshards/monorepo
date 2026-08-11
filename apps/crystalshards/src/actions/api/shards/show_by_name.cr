# The old bare-name API path, kept for existing clients.
#
# Same rule as the browser: a name is answerable only while it names one
# shard. One identified shard redirects to its canonical API path, one legacy
# row without identity is served directly because it has no canonical path,
# and an ambiguous name is a 409 carrying the candidates so a client can pick
# the repository it actually meant instead of being handed a guess.
class Api::Shards::ShowByName < ApiAction
  include Api::Auth::SkipRequireAuthToken

  get "/api/shards/:shard_name" do
    matches = ShardQuery.new
      .preload_shard_versions
      .name(shard_name)
      .limit(2)
      .to_a

    case matches.size
    when 0
      head 404
    when 1
      serve(matches.first)
    else
      json({
        error:      "#{shard_name} names more than one shard. Request it by repository.",
        candidates: ShardQuery.new.name(shard_name).to_a.map { |shard| shard.url_path },
      }, status: 409)
    end
  end

  private def serve(shard : Shard)
    if slug = shard.canonical_slug
      parts = slug.split('/')
      redirect to: Api::Shards::Show.with(
        host: parts[0],
        owner: parts[1],
        repo: parts[2]
      ).path, status: 301
    else
      json ShardPayload.detail(shard)
    end
  end
end
