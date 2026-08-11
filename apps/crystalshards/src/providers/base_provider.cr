require "yaml"
require "../services/git_host_policy"

abstract class BaseProvider
  getter repository_url : String

  def initialize(@repository_url : String)
  end

  abstract def fetch_shard_yml(version : String?) : YAML::Any?
  abstract def fetch_metadata : RepositoryMetadata?
  abstract def clone_repository(target_dir : String) : Bool
  abstract def checkout_version(repo_dir : String, version : String) : Bool

  # Every provider that clones over git shares these two. They used to be
  # copy-pasted into five providers as backtick strings with the URL, the
  # directory and the version interpolated straight into a shell command, so
  # any of those three could carry `$(...)` and run as our process. These run
  # the binary directly with an argument array: there is no shell to inject
  # into, and the URL is re-checked here because a provider can be constructed
  # without going through ProviderFactory.
  def clone_git_repository(target_dir : String) : Bool
    url = GitHostPolicy.normalize_url(repository_url)
    GitHostPolicy.validate_fetch_url!(url)

    run_process("git", ["clone", "--depth", "1", "--", url, target_dir])
  rescue ex : GitHostPolicy::UnsafeUrlError
    Log.warn { "Refusing to clone #{repository_url.inspect}: #{ex.message}" }
    false
  end

  def checkout_git_version(repo_dir : String, version : String) : Bool
    return false unless safe_ref?(version)

    if run_process("git", ["fetch", "--depth", "1", "origin", "tag", version], chdir: repo_dir) &&
       run_process("git", ["checkout", version], chdir: repo_dir)
      return true
    end

    run_process("git", ["fetch", "--depth", "1", "origin", version], chdir: repo_dir) &&
      run_process("git", ["checkout", version], chdir: repo_dir)
  end

  # A ref reaches the command line as an argument, so it cannot inject a
  # command, but it can still be read as an option ("--upload-pack=...") or
  # walk out of the repository. Refs the registry stores are tags and
  # branches; anything else is refused rather than sanitized.
  protected def safe_ref?(version : String) : Bool
    return false if version.empty? || version.size > 200
    return false if version.starts_with?('-')
    return false if version.includes?("..") || version.includes?('\0')

    version.matches?(/\A[A-Za-z0-9._\/+-]+\z/)
  end

  protected def run_process(command : String, args : Array(String), chdir : String? = nil) : Bool
    output = IO::Memory.new
    status = Process.run(command, args, chdir: chdir, output: output, error: output)
    unless status.success?
      Log.debug { "#{command} #{args.join(' ')} failed: #{output.to_s.lines.first?}" }
    end
    status.success?
  rescue ex : IO::Error | File::Error
    Log.warn { "#{command} could not be run: #{ex.message}" }
    false
  end

  # Providers that can serve a README override this. Returning nil means
  # "no README available", never "pretend there is one".
  def fetch_readme(version : String? = nil) : String?
    nil
  end

  # The registry stores normalized versions ("1.2.3") but Crystal shards are
  # conventionally tagged "v1.2.3". Fetching the normalized string straight
  # from a forge 404s, so resolve against both spellings.
  def candidate_refs(version : String?) : Array(String)
    return ["HEAD"] unless version && !version.empty?

    if version.starts_with?('v')
      [version, version.lchop('v')]
    else
      [version, "v#{version}"]
    end
  end

  def extract_repo_path : String?
    nil
  end

  def supports_api? : Bool
    false
  end

  def repository_type : String
    "git"
  end

  def provider_name : String
    self.class.name.underscore.sub("_provider", "")
  end

  class RepositoryMetadata
    property stars : Int32?
    property forks : Int32?
    property description : String?
    property homepage : String?
    property default_branch : String?
    property latest_commit_sha : String?

    def initialize(
      @stars = nil,
      @forks = nil,
      @description = nil,
      @homepage = nil,
      @default_branch = nil,
      @latest_commit_sha = nil,
    )
    end
  end
end
