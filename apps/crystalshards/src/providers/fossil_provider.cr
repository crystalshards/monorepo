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
    fossil_file = File.join(target_dir, "repo.fossil")
    work_dir = File.join(target_dir, "checkout")

    clone_cmd = "fossil clone #{repository_url} #{fossil_file}"
    clone_output = `#{clone_cmd} 2>&1`

    return false unless $?.success?

    open_cmd = "cd #{work_dir} && fossil open #{fossil_file}"
    open_output = `#{open_cmd} 2>&1`

    $?.success?
  end

  def checkout_version(repo_dir : String, version : String) : Bool
    work_dir = File.join(repo_dir, "checkout")

    cmd = "cd #{work_dir} && fossil update #{version}"
    output = `#{cmd} 2>&1`

    if $?.success?
      true
    else
      cmd = "cd #{work_dir} && fossil update tag:#{version}"
      output = `#{cmd} 2>&1`
      $?.success?
    end
  end

  def supports_api? : Bool
    false
  end

  def repository_type : String
    "fossil"
  end
end
