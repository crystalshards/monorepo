class Home::Index < BrowserAction
  get "/" do
    featured_shards = ShardQuery.new
      .preload_shard_versions
      .github_stars.desc_order
      .limit(6)
      .to_a

    recent_shards = ShardQuery.new
      .preload_shard_versions
      .updated_at.desc_order
      .limit(6)
      .to_a

    total_shards = ShardQuery.new.select_count
    total_downloads = DownloadQuery.new.select_count

    html Home::IndexPage,
      featured_shards: featured_shards,
      recent_shards: recent_shards,
      total_shards: total_shards,
      total_downloads: total_downloads
  end
end
