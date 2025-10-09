class ShardCard < Lucky::BaseComponent
  needs shard : Shard

  def render
    article class: "shard-card" do
      div class: "shard-card-header" do
        h3 class: "shard-name" do
          a href: "/shards/#{@shard.name}" do
            text @shard.name
          end
        end

        if stars = @shard.github_stars
          span class: "shard-stars" do
            text "⭐ #{stars}"
          end
        end
      end

      if description = @shard.description
        para class: "shard-description" do
          text description
        end
      end

      div class: "shard-meta" do
        if license = @shard.license
          span class: "shard-license" do
            text "License: #{license}"
          end
        end

        span class: "shard-downloads" do
          text "#{@shard.total_downloads} downloads"
        end
      end
    end
  end
end
