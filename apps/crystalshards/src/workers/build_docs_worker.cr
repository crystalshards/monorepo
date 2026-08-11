require "./base_worker"
require "../services/docs_builder"
require "../services/storage_service"
require "../services/docs_build_status"

struct BuildDocsWorker < BaseJob
  # The only job that is never run where it was asked for.
  #
  # A build compiles code the shard author wrote, and Crystal expands macros
  # while compiling, so `crystal docs` on a third party shard is arbitrary
  # command execution. This process holds the registry database and object
  # storage credentials, so the request goes to Cloud Tasks, the launcher
  # starts a Cloud Run Job that holds no credentials, and `perform` below runs
  # only in the launcher.
  #
  # Returns the build id, or nil when the request could not be delivered.
  def self.enqueue(shard_name : String, version : String) : String?
    CrystalShards::JobQueue.current.build_docs(shard_name, version)
  end

  # @shard_name is the wire field name crystaldocs already produces, so it
  # stays. What it CARRIES is now the canonical slug
  # ("github.com/kemalcr/kemal") for anything crystalshards enqueues, because
  # a bare name cannot say which of two same-named shards to build.
  # ShardQuery#resolve accepts either, and refuses an ambiguous bare name
  # rather than building the wrong repository. crystaldocs still sends bare
  # names and keeps working until the day a name collides.
  def initialize(@shard_name : String, @version : String)
    @queue = "docs"
  end

  # crystaldocs queues this job the first time anyone asks for a version it
  # has no artifact for, and shows that reader a pending page until this job
  # says otherwise. Every exit from this method therefore reports an outcome.
  # A path that returns quietly leaves a reader watching a page that refreshes
  # forever, and leaves the retry floor with no failed_at to measure from, so
  # the version is never reconsidered either.
  def perform
    log_info "Building docs for: #{@shard_name}@#{@version}"
    docs_status.building

    shard = ShardQuery.new.resolve(@shard_name)
    unless shard
      log_error "Shard not found: #{@shard_name}"
      docs_status.failed(
        "No single shard in the registry answers to #{@shard_name}. Either it is " \
        "not registered, or the name belongs to more than one repository and the " \
        "build has to name one, as in github.com/owner/repo."
      )
      return
    end

    shard_version = ShardVersionQuery.new
      .shard_id(shard.id.not_nil!)
      .version(@version)
      .first?

    unless shard_version
      log_error "Shard version not found: #{@shard_name}@#{@version}"
      docs_status.failed("#{@shard_name} has no published version #{@version} in the registry.")
      return
    end

    docs_url = build_and_upload_docs(shard, shard_version)

    if docs_url
      operation = SaveShard.new(shard)
      operation.documentation_url.value = docs_url
      operation.update!
      docs_status.succeeded
      log_info "Successfully built docs for #{@shard_name}@#{@version}: #{docs_url}"
    else
      log_error "Failed to build docs for #{@shard_name}@#{@version}"
      docs_status.failed("crystal docs produced no output for #{@shard_name} #{@version}. Usually the shard does not compile against the Crystal version it declared.")
    end
  rescue ex : Exception
    log_error "Failed to build docs for #{@shard_name}@#{@version}", ex
    # Recorded before re-raising, so the reader sees a failure even though
    # Cloud Tasks will redeliver the request. A retry that succeeds overwrites
    # this; one that fails again just refreshes failed_at.
    docs_status.failed(ex.message)
    raise ex
  end

  # Named docs_status, not status, so it cannot be confused with the build
  # request's own lifecycle column of the same name, which crystaldocs owns
  # and this only ever writes through the statements in DocsBuildStatus.
  private def docs_status : CrystalShards::DocsBuildStatus
    CrystalShards::DocsBuildStatus.new(@shard_name, @version)
  end

  private def build_and_upload_docs(shard : Shard, shard_version : ShardVersion) : String?
    temp_dir = File.tempname("shard_docs")
    Dir.mkdir_p(temp_dir)

    begin
      docs_json = CrystalShards::DocsBuilder.build.generate_docs(
        shard.repository_url,
        shard_version.version,
        shard_version.commit_sha,
        temp_dir
      )
      return nil unless docs_json

      upload_to_storage(shard, shard_version, docs_json)
    ensure
      FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
    end
  end

  private def upload_to_storage(shard : Shard, shard_version : ShardVersion, docs_json : String) : String
    storage = CrystalShards::StorageService.build
    key = storage.upload_docs_json(shard.name, shard_version.version, docs_json)

    log_info "Uploaded #{key} (#{File.size(docs_json)} bytes) to object storage"
    "https://crystaldocs.org/#{shard.name}/#{shard_version.version}"
  rescue ex : Exception
    log_error "Error uploading docs to object storage", ex
    raise ex
  end
end
