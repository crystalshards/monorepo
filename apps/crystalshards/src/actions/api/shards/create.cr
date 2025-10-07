require "../../../services/storage_service"

class Api::Shards::Create < ApiAction
  include Lucky::RateLimit
  rate_limit to: 10, within: 1.hour

  post "/api/shards" do
    # Accept JSON payload with shard metadata
    # File upload is handled by a separate endpoint for now
    # TODO: Add multipart support using Shrine or similar

    SaveShard.create(
      name: params.get("name"),
      description: params.get?("description"),
      repository_url: params.get("repository_url"),
      homepage_url: params.get?("homepage_url"),
      documentation_url: params.get?("documentation_url"),
      license: params.get?("license")
    ) do |operation, shard|
      if shard
        version_string = params.get("version")

        # Enqueue worker to index the shard (parse shard.yml, create version, upload package)
        IndexShardWorker.new(
          shard_name: shard.name,
          version: version_string
        ).enqueue

        json({
          message: "Shard created successfully, indexing started",
          shard:   {
            id:   shard.id,
            name: shard.name,
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
