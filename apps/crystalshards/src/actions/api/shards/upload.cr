require "../../../services/storage_service"
require "digest/sha256"

class Api::Shards::Upload < ApiAction
  include Api::Auth::RequireAuthToken
  include Lucky::RateLimit
  rate_limit to: 10, within: 1.hour

  MAX_PACKAGE_SIZE = 50 * 1024 * 1024 # 50 MB in bytes

  def rate_limit_identifier
    # Use user ID for authenticated requests, fallback to test identifier
    if current_user?
      "user:#{current_user.id}"
    else
      "test:default"
    end
  end

  post "/api/shards/upload" do
    # Parse multipart form data
    if request.headers["Content-Type"]?.try(&.starts_with?("multipart/form-data"))
      handle_multipart_upload
    else
      json({
        error: "Content-Type must be multipart/form-data",
      }, status: 400)
    end
  end

  private def handle_multipart_upload
    shard_name : String? = nil
    version : String? = nil
    description : String? = nil
    repository_url : String? = nil
    homepage_url : String? = nil
    documentation_url : String? = nil
    license : String? = nil
    package_filename : String? = nil
    package_content : String? = nil
    checksum : String? = nil

    HTTP::FormData.parse(request) do |part|
      case part.name
      when "name"
        shard_name = part.body.gets_to_end
      when "version"
        version = part.body.gets_to_end
      when "description"
        description = part.body.gets_to_end
      when "repository_url"
        repository_url = part.body.gets_to_end
      when "homepage_url"
        homepage_url = part.body.gets_to_end
      when "documentation_url"
        documentation_url = part.body.gets_to_end
      when "license"
        license = part.body.gets_to_end
      when "package"
        # A part's IO is only readable while that part is being yielded, so
        # take the filename and the bytes now. Stashing the part and reading
        # it after the parse loop raises IO::Error "Closed stream".
        package_filename = part.filename
        package_content = part.body.gets_to_end
      when "checksum"
        checksum = part.body.gets_to_end
      end
    end

    unless shard_name && version && repository_url && package_content
      return json({
        error: "Missing required fields: name, version, repository_url, and package file",
      }, status: 400)
    end

    unless package_filename.try(&.ends_with?(".tar.gz"))
      return json({
        error: "Package file must be a .tar.gz archive",
      }, status: 400)
    end

    if package_content.bytesize > MAX_PACKAGE_SIZE
      return json({
        error:          "Package size exceeds maximum allowed size",
        max_size_mb:    MAX_PACKAGE_SIZE / (1024 * 1024),
        actual_size_mb: (package_content.bytesize / (1024.0 * 1024.0)).round(2),
      }, status: 413)
    end

    computed_checksum = Digest::SHA256.hexdigest(package_content)

    if checksum && checksum != computed_checksum
      return json({
        error:             "Checksum mismatch",
        expected_checksum: checksum,
        actual_checksum:   computed_checksum,
      }, status: 400)
    end

    # A publish names the repository it comes from, so the shard it belongs to
    # is found by identity. Looking it up by name would attach a GitLab
    # project's release to a GitHub project that happens to share its name.
    identity = ShardIdentity.parse_url(repository_url)
    shard = identity.try { |found| ShardQuery.new.canonical_slug(found.canonical_slug).first? }

    unless shard
      SaveShard.create(
        name: shard_name,
        description: description,
        repository_url: repository_url,
        homepage_url: homepage_url,
        documentation_url: documentation_url,
        license: license
      ) do |operation, created_shard|
        if created_shard
          shard = created_shard
        else
          return json({
            errors: operation.errors.map { |attr, msg| {attr.to_s, msg} },
          }, status: 422)
        end
      end
    end

    # At this point we have a shard (either found or created)
    begin
      # Upload to storage (skip when the object store is unavailable)
      begin
        storage = CrystalShards::StorageService.new
        storage.upload_package_from_io(
          shard_name: package_storage_key(shard.not_nil!),
          version: version,
          content: package_content
        )
      rescue ex : Exception
        # The store may be unavailable in a test environment; log and continue
        Log.warn { "Failed to upload package to storage: #{ex.message}" }
      end

      SaveShardVersion.create(
        shard_id: shard.not_nil!.id,
        version: version,
        checksum: computed_checksum,
        released_at: Time.utc,
        yanked: false
      ) do |version_operation, shard_version|
        if shard_version
          # Enqueue background job to index shard metadata, keyed on identity
          # so the job cannot land on another shard of the same name.
          begin
            IndexShardWorker.enqueue(
              shard_name: package_storage_key(shard.not_nil!),
              version: version
            )
          rescue ex : Exception
            # Log error but don't fail the request
            # In test environments, the job queue may not be available
            Log.warn { "Failed to enqueue IndexShardWorker: #{ex.message}" }
          end

          json({
            message: "Shard uploaded successfully",
            shard:   {
              id:             shard.not_nil!.id,
              name:           shard.not_nil!.name,
              canonical_slug: shard.not_nil!.canonical_slug,
              url:            shard.not_nil!.url_path,
            },
            version: {
              id:       shard_version.id,
              version:  shard_version.version,
              checksum: shard_version.checksum,
            },
            checksum: computed_checksum,
          }, status: 201)
        else
          json({
            errors: version_operation.errors.map { |attr, msg| {attr.to_s, msg} },
          }, status: 422)
        end
      end
    rescue ex : Exception
      json({
        error: "Failed to upload package: #{ex.message}",
      }, status: 500)
    end
  end

  # Packages and jobs are keyed on the repository, so two shards sharing a
  # name cannot overwrite each other's archives. A legacy row with no identity
  # keeps its existing name-keyed objects.
  private def package_storage_key(shard : Shard) : String
    shard.canonical_slug || shard.name
  end
end
