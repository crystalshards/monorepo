require "./base_provider"

class FossilProvider < BaseProvider
  def fetch_shard_yml(version : String? = nil) : YAML::Any?
    temp_dir = File.tempname("shard_fetch")
    work_dir = File.join(temp_dir, "checkout")
    Dir.mkdir_p(temp_dir)
    Dir.mkdir_p(work_dir)

    begin
      return nil unless clone_repository(temp_dir)

      if version
        checkout_version(temp_dir, version)
      end

      shard_yml_path = File.join(work_dir, "shard.yml")
      return nil unless File.exists?(shard_yml_path)

      YAML.parse(File.read(shard_yml_path))
    ensure
      FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
    end
  rescue ex : Exception
    Log.error { "Failed to fetch shard.yml from Fossil: #{ex.message}" }
    nil
  end

  def fetch_metadata : RepositoryMetadata?
    RepositoryMetadata.new
  end

  def clone_repository(target_dir : String) : Bool
    url = GitHostPolicy.normalize_url(repository_url)
    GitHostPolicy.validate_fetch_url!(url)

    fossil_file = File.join(target_dir, "repo.fossil")
    work_dir = File.join(target_dir, "checkout")

    return false unless run_process("fossil", ["clone", url, fossil_file])

    run_process("fossil", ["open", fossil_file], chdir: work_dir)
  rescue ex : GitHostPolicy::UnsafeUrlError
    Log.warn { "Refusing to clone #{repository_url.inspect}: #{ex.message}" }
    false
  end

  def checkout_version(repo_dir : String, version : String) : Bool
    return false unless safe_ref?(version)

    work_dir = File.join(repo_dir, "checkout")

    return true if run_process("fossil", ["update", version], chdir: work_dir)

    run_process("fossil", ["update", "tag:#{version}"], chdir: work_dir)
  end

  def supports_api? : Bool
    false
  end

  def repository_type : String
    "fossil"
  end
end
