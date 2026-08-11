require "../../../services/storage_service"

class Api::Shards::Create < ApiAction
  include Lucky::RateLimit
  rate_limit to: 10, within: 1.hour

  def rate_limit_identifier
    # Use user ID for authenticated requests, fallback to test identifier
    if current_user?
      "user:#{current_user.id}"
    else
      # For test environment or when IP is not available
      "test:default"
    end
  end

  post "/api/shards" do
    # Accept JSON payload with shard metadata
    # For file uploads with packages, use POST /api/shards/upload (multipart/form-data)
    #
    # Identity is derived from repository_url by SaveShard, so a submission
    # whose URL does not name one repository on one host is rejected here
    # rather than becoming a row nothing can index or address.

    SaveShard.create(params) do |operation, shard|
      if shard
        version_string = params.get?(:version)

        if version_string
          # Enqueue worker to index the shard (parse shard.yml, create version, upload package)
          begin
            IndexShardWorker.enqueue(
              shard_name: shard.canonical_slug.not_nil!,
              version: version_string
            )
          rescue ex : Exception
            # Log error but don't fail the request
            # In test environments, the job queue may not be available
            Log.warn { "Failed to enqueue IndexShardWorker: #{ex.message}" }
          end
        end

        json({
          message: "Shard created successfully" + (version_string ? ", indexing started" : ""),
          shard:   {
            id:             shard.id,
            name:           shard.name,
            canonical_slug: shard.canonical_slug,
            url:            shard.url_path,
          },
        }, status: 201)
      else
        json({
          errors: operation.errors.map { |attr, msg| {attr.to_s, msg} },
        }, status: 422)
      end
    end
  end
end
