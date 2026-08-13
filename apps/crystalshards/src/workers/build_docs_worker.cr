require "./base_worker"
require "../services/docs_builder"
require "../services/storage_service"
require "../services/docs_build_status"
require "../services/core_docs"

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
  #
  # It no longer writes `documentation_url`. That column holds the link a
  # maintainer declared, and overwriting it on every successful build both
  # destroyed what they declared and turned the `has_docs` filter into "we
  # generated API docs", which is not what the column says and not what a
  # reader filtering on it is asking for. Nothing needs the write any more:
  # every shard now has a documentation URL by virtue of having an identity,
  # computed by `CrystalShards::DocsSite`, so the field being set is no longer
  # how the site knows documentation exists.
  def perform
    log_info "Building docs for: #{@shard_name}@#{@version}"

    # The standard library is not a registry shard: it has no ShardQuery
    # entry, no commit_sha, and no `docs` row until something writes one.
    # CrystalShards::CoreDocs owns that whole lifecycle, including its own
    # registration and its own DocsBuildStatus writes, so this hands off
    # entirely rather than threading a special case through ShardQuery and
    # DocsBuilder below, both of which assume a registry entry exists.
    return perform_core_build if CrystalShards::CoreDocs.package?(@shard_name)

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

    builder = CrystalShards::DocsBuilder.build
    key = build_and_upload_docs(builder, shard, shard_version)

    if key
      docs_status.succeeded
      log_info "Successfully built docs for #{@shard_name}@#{@version}: #{key}"
    else
      log_error "Failed to build docs for #{@shard_name}@#{@version}"
      # The builder's account of the failure, not a standing guess. The old
      # sentence here blamed the shard's declared Crystal version for every
      # failure, which since the compile lost its network is often the wrong
      # thing to send someone chasing.
      docs_status.failed(
        builder.failure_reason ||
        "crystal docs produced no output for #{@shard_name} #{@version}, and the build did not say why."
      )
    end
  rescue ex : CrystalShards::DocsBuildStatus::Unrecorded
    # An outcome this method already decided could not be written down. It is
    # NOT a build failure and must not be recorded as one: the build it
    # describes may well have succeeded and uploaded its artifact, and the
    # write that would say so is the write that just failed. Trying again with
    # 'failed' over the same connection cannot work and would be a lie if it
    # did.
    #
    # DocsBuildStatus has already logged this against the package and version.
    # Raising fails the job, so Cloud Tasks redelivers, and the redelivery
    # rebuilds and records again. That redelivery is the only thing that
    # repairs a lost outcome, which is why this is raised rather than
    # absorbed.
    raise ex
  rescue ex : Exception
    log_error "Failed to build docs for #{@shard_name}@#{@version}", ex

    # Recorded before re-raising, so the reader sees a failure even though
    # Cloud Tasks will redeliver the request. A retry that succeeds overwrites
    # this; one that fails again just refreshes failed_at.
    begin
      docs_status.failed(ex.message)
    rescue CrystalShards::DocsBuildStatus::Unrecorded
      # Already logged there, against this package and version. The build's own
      # exception is the one worth raising: it is why this path was taken, and
      # the job fails on either, which is what puts the request back on the
      # queue.
    end

    raise ex
  end

  # CrystalShards::CoreDocs.build_and_publish already registers the version,
  # writes 'building' before it clones anything, and writes 'succeeded' or
  # 'failed' through the same DocsBuildStatus every shard build uses, so
  # nothing here duplicates those writes. This only logs the outcome and
  # re-raises on failure, matching `perform`'s own contract: raising is what
  # puts a redelivered request back through Cloud Tasks.
  private def perform_core_build
    published = CrystalShards::CoreDocs.build_and_publish(@version)
    if published.reused_existing
      log_info "The standard library #{@shard_name}@#{@version} was already present at #{published.key}; " \
               "marked success from the artifact and skipped rebuilding"
    else
      log_info "Successfully published the standard library #{@shard_name}@#{@version}: " \
               "#{published.key} (#{published.bytes} bytes, #{published.types} types)"
    end
  rescue ex : Exception
    log_error "Failed to publish the standard library #{@shard_name}@#{@version}", ex
    raise ex
  end

  # Named docs_status, not status, so it cannot be confused with the build
  # request's own lifecycle column of the same name, which crystaldocs owns
  # and this only ever writes through the statements in DocsBuildStatus.
  private def docs_status : CrystalShards::DocsBuildStatus
    CrystalShards::DocsBuildStatus.new(@shard_name, @version)
  end

  private def build_and_upload_docs(builder : CrystalShards::DocsBuilder, shard : Shard, shard_version : ShardVersion) : String?
    temp_dir = File.tempname("shard_docs")
    Dir.mkdir_p(temp_dir)

    begin
      docs_json = builder.generate_docs(
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

  # The artifact is stored under the key the build was ASKED for, not under the
  # shard's name.
  #
  # Those were the same thing only while every requester sent a bare name. They
  # are not now: crystaldocs addresses a package by its repository, requests
  # the build under that key and reads the result back from it, so storing
  # under `shard.name` would put the artifact somewhere the reader never looks
  # and leave the version rebuilding forever. It would also give two shards
  # called "lsp" one key between them, which is the collision the host
  # qualified key exists to remove.
  #
  # `ShardQuery#resolve` has already established that this key names exactly
  # this shard, so it is a key we own rather than free text from a request.
  private def upload_to_storage(shard : Shard, shard_version : ShardVersion, docs_json : String) : String
    storage = CrystalShards::StorageService.build
    key = storage.upload_docs_json(@shard_name, shard_version.version, docs_json)

    log_info "Uploaded #{key} (#{File.size(docs_json)} bytes) to object storage"
    key
  rescue ex : Exception
    log_error "Error uploading docs to object storage", ex
    raise ex
  end
end
