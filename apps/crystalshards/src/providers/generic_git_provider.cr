require "./base_provider"

class GenericGitProvider < BaseProvider
  def fetch_shard_yml(version : String? = nil) : YAML::Any?
    temp_dir = File.tempname("shard_fetch")
    Dir.mkdir_p(temp_dir)

    begin
      return nil unless clone_repository(temp_dir)

      if version
        checkout_version(temp_dir, version)
      end

      shard_yml_path = File.join(temp_dir, "shard.yml")
      return nil unless File.exists?(shard_yml_path)

      YAML.parse(File.read(shard_yml_path))
    ensure
      FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
    end
  rescue ex : Exception
    Log.error { "Failed to fetch shard.yml from generic Git: #{ex.message}" }
    nil
  end

  def fetch_metadata : RepositoryMetadata?
    RepositoryMetadata.new
  end

  def clone_repository(target_dir : String) : Bool
    clone_git_repository(target_dir)
  end

  def checkout_version(repo_dir : String, version : String) : Bool
    checkout_git_version(repo_dir, version)
  end

  def supports_api? : Bool
    false
  end
end
