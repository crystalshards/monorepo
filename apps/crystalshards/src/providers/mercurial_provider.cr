require "./base_provider"

class MercurialProvider < BaseProvider
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
    Log.error { "Failed to fetch shard.yml from Mercurial: #{ex.message}" }
    nil
  end

  def fetch_metadata : RepositoryMetadata?
    RepositoryMetadata.new
  end

  def clone_repository(target_dir : String) : Bool
    url = GitHostPolicy.normalize_url(repository_url)
    GitHostPolicy.validate_fetch_url!(url)

    run_process("hg", ["clone", "--", url, target_dir])
  rescue ex : GitHostPolicy::UnsafeUrlError
    Log.warn { "Refusing to clone #{repository_url.inspect}: #{ex.message}" }
    false
  end

  def checkout_version(repo_dir : String, version : String) : Bool
    return false unless safe_ref?(version)

    return true if run_process("hg", ["update", "-r", version], chdir: repo_dir)

    run_process("hg", ["update", "-r", "tag(#{version})"], chdir: repo_dir)
  end

  def supports_api? : Bool
    false
  end

  def repository_type : String
    "mercurial"
  end
end
