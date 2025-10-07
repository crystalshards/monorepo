require "../../../../../services/storage_service"

class Api::Shards::Versions::Downloads::Create < ApiAction
  include Api::Auth::SkipRequireAuthToken

  post "/api/shards/:shard_name/:version_number/download" do
    shard = ShardQuery.new.name(shard_name).first?

    if shard.nil?
      head 404
    else
      version = ShardVersionQuery.new
        .shard_id(shard.id.not_nil!)
        .version(version_number)
        .first?

      if version.nil?
        head 404
      elsif version.yanked
        json({error: "This version has been yanked and is no longer available"}, status: 410)
      else
        # Track download
        SaveDownload.create!(
          shard_version_id: version.id.not_nil!,
          ip_address: request.remote_address.to_s,
          user_agent: request.headers["User-Agent"]? || "unknown",
          country_code: request.headers["CF-IPCountry"]?,
          downloaded_at: Time.utc
        )

        SaveShard.update!(shard, total_downloads: shard.total_downloads + 1)

        # Return presigned URL for actual download
        # This allows MinIO to serve the file directly without going through our app
        begin
          storage = CrystalShards::StorageService.new
          download_url = storage.package_download_url(shard.name, version.version)

          json({
            shard_name:   shard.name,
            version:      version.version,
            download_url: download_url,
            message:      "Download URL generated",
          })
        rescue ex
          Log.error { "Failed to generate download URL: #{ex.message}" }
          json({error: "Package not available"}, status: 500)
        end
      end
    end
  end
end
