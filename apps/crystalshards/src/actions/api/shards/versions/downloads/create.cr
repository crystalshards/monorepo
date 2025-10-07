class Api::Shards::Versions::Downloads::Create < ApiAction
  include Api::Auth::SkipRequireAuthToken

  post "/api/shards/:shard_name/:version_number/download" do
    shard = ShardQuery.new.name(shard_name).first?

    if shard.nil?
      head 404
    else
      version = ShardVersionQuery.new
        .shard_id(shard.id)
        .version(version_number)
        .first?

      if version.nil?
        head 404
      elsif version.yanked
        json({error: "This version has been yanked and is no longer available"}, status: 410)
      else
        SaveDownload.create!(
          shard_version_id: version.id,
          ip_address: request.remote_address.to_s,
          user_agent: request.headers["User-Agent"]? || "unknown",
          country_code: request.headers["CF-IPCountry"]?,
          downloaded_at: Time.utc
        )

        SaveShard.update!(shard, total_downloads: shard.total_downloads + 1)

        json({
          shard_name: shard.name,
          version:    version.version,
          message:    "Download tracked successfully",
        })
      end
    end
  end
end
