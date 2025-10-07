class ShardFactory < Avram::Factory
  def initialize
    name "sample-shard"
    repository_url "https://github.com/crystal-lang/sample-shard"
    description "A sample Crystal shard"
    total_downloads 0
  end
end
