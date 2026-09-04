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
        indexing_started = false

        if version_string
          # Normalise the version tag the same way GitHub webhooks do by
          # stripping any leading 'v', so 'v1.2.0' and '1.2.0' cannot become
          # two rows for one release.
          version = version_string.sub(/^v/, "")

          # The version row must exist before the job runs: IndexShardWorker looks it
          # up and exits immediately if it is missing.
          if ShardVersionQuery.new.shard_id(shard.id).version(version).first?
            Log.info { "Shard version already exists: #{shard.canonical_slug}@#{version}" }
          else
            SaveShardVersion.create(
              shard_id: shard.id,
              version: version,
              yanked: false,
              released_at: Time.utc
            ) do |version_operation, shard_version|
              if shard_version
                # Enqueue worker to index the shard (parse shard.yml, extract metadata, upload package)
                begin
                  IndexShardWorker.enqueue(
                    shard_name: shard.canonical_slug.not_nil!,
                    version: version
                  )
                  indexing_started = true
                rescue ex : Exception
                  # Log error but don't fail the request.
                  # In test environments, the job queue may not be available.
                  Log.warn { "Failed to enqueue IndexShardWorker: #{ex.message}" }
                end
              else
                # If SaveShardVersion fails (for example on a blank version string),
                # the shard itself was still successfully created in the registry,
                # so returning HTTP 201 is still right. However, because no version
                # row was persisted, IndexShardWorker cannot run and indexing did
                # not start, so the response message must not claim that it did.
                Log.warn { "Failed to create ShardVersion for #{shard.canonical_slug}@#{version}: #{version_operation.errors}" }
              end
            end
          end
        end

        message = "Shard created successfully"
        message += ", indexing started" if indexing_started

        json({
          message: message,
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
