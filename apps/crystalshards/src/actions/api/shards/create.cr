class Api::Shards::Create < ApiAction
  post "/api/shards" do
    # TODO: Extract shard info from request
    # This will need to parse uploaded shard.yml or fetch from git repo

    SaveShard.create(
      name: params.get("name"),
      description: params.get?("description"),
      repository_url: params.get("repository_url"),
      homepage_url: params.get?("homepage_url"),
      documentation_url: params.get?("documentation_url"),
      license: params.get?("license")
    ) do |operation, shard|
      if shard
        # Enqueue worker to index the shard
        IndexShardWorker.new(
          shard_name: shard.name,
          version: params.get("version")
        ).enqueue

        json({
          message: "Shard created successfully",
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
