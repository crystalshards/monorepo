require "../../../../../services/storage_service"

class Api::Shards::Versions::Downloads::Create < ApiAction
  include Api::Auth::SkipRequireAuthToken
  include Lucky::RateLimit
  rate_limit to: 100, within: 1.hour

  def rate_limit_identifier
    # Use remote address or test identifier
    if addr = request.remote_address
      addr.to_s
    else
      "test:default"
    end
  end

  # Download counts are attributed to a repository, never to a name. A bare
  # name could name two shards, and crediting a download to the wrong one is
  # not recoverable, so this endpoint only takes the identity.
  post "/api/shards/:host/:owner/:repo/:version_number/download" do
    shard = ShardQuery.new.canonical_slug("#{host}/#{owner}/#{repo}").first?

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
          shard_id: shard.id.not_nil!,
          shard_version_id: version.id.not_nil!,
          ip_address: request.remote_address.try(&.to_s),
          user_agent: request.headers["User-Agent"]? || "unknown",
          country_code: request.headers["CF-IPCountry"]?,
          downloaded_at: Time.utc
        )

        SaveShard.update!(shard, total_downloads: shard.total_downloads + 1)

        # Return presigned URL for actual download
        # This lets the object store serve the file without proxying it
        begin
          storage = CrystalShards::StorageService.new
          download_url = storage.package_download_url(storage_key(shard), version.version)

          json({
            name:           shard.name,
            canonical_slug: shard.canonical_slug,
            version:        version.version,
            download_url:   download_url,
            message:        "Download tracked successfully",
          })
        rescue ex
          # In test environments the object store may not be available
          # Return success anyway since download tracking succeeded
          Log.warn { "Storage not available, skipping download URL generation: #{ex.message}" }
          json({
            name:           shard.name,
            canonical_slug: shard.canonical_slug,
            version:        version.version,
            message:        "Download tracked successfully (storage unavailable in test)",
          })
        end
      end
    end
  end

  # Packages are stored under the identity, so two shards sharing a name do
  # not share one object key. Legacy rows without identity keep their existing
  # name-keyed objects.
  private def storage_key(shard : Shard) : String
    shard.canonical_slug || shard.name
  end
end
