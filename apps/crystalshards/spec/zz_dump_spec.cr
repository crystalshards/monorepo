require "./spec_helper"

describe "TEMP query dump" do
  it "dumps listing queries" do
    20.times { |i| ShardFactory.create &.name("shard-#{i}").github_stars(i) }

    queries = QueryCounter.record { BrowserClient.exec(Shards::Index) }
    puts "\n===== /shards : #{queries.size} queries ====="
    queries.each_with_index { |q, i| puts "--- #{i + 1} ---\n#{q.gsub(/\s+/, " ").strip}" }

    home = QueryCounter.record { BrowserClient.exec(Home::Index) }
    puts "\n===== / : #{home.size} queries ====="
    home.each_with_index { |q, i| puts "--- #{i + 1} ---\n#{q.gsub(/\s+/, " ").strip}" }
  end
end
