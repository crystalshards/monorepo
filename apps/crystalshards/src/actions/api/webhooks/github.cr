require "openssl/hmac"
require "json"

class Api::Webhooks::Github < ApiAction
  include Api::Auth::SkipRequireAuthToken

  post "/api/webhooks/github" do
    signature = request.headers["X-Hub-Signature-256"]?
    event_type = request.headers["X-GitHub-Event"]?

    unless signature
      return json({
        error: "Missing signature",
      }, status: 400)
    end

    body = request.body.try(&.gets_to_end) || "{}"

    unless verify_signature(signature, body)
      return json({
        error: "Invalid signature",
      }, status: 400)
    end

    begin
      payload = JSON.parse(body)

      case event_type
      when "release"
        handle_release_event(payload)
      when "create"
        handle_create_event(payload)
      else
        json({
          error: "Not a relevant event",
        }, status: 422)
      end
    rescue ex : JSON::ParseException
      json({
        error: "Invalid JSON payload",
      }, status: 400)
    rescue ex : Exception
      json({
        error: "Internal server error: #{ex.message}",
      }, status: 500)
    end
  end

  private def verify_signature(signature : String, body : String) : Bool
    secret = ENV["GITHUB_WEBHOOK_SECRET"]? || "test_webhook_secret"
    expected_signature = "sha256=" + OpenSSL::HMAC.hexdigest(OpenSSL::Algorithm::SHA256, secret, body)
    Crypto::Subtle.constant_time_compare(signature, expected_signature)
  end

  private def handle_release_event(payload : JSON::Any)
    action = payload["action"]?.try(&.as_s)

    unless action == "published" || action == "created"
      return json({
        error: "Not a relevant event",
      }, status: 422)
    end

    repository_url = payload["repository"]?
      .try(&.["html_url"]?)
      .try(&.as_s)

    tag_name = payload["release"]?
      .try(&.["tag_name"]?)
      .try(&.as_s)

    unless repository_url && tag_name
      return json({
        error: "Missing required fields",
      }, status: 400)
    end

    process_version(repository_url, tag_name)
  end

  private def handle_create_event(payload : JSON::Any)
    ref_type = payload["ref_type"]?.try(&.as_s)

    unless ref_type == "tag"
      return json({
        error: "Not a relevant event",
      }, status: 422)
    end

    repository_url = payload["repository"]?
      .try(&.["html_url"]?)
      .try(&.as_s)

    tag_name = payload["ref"]?.try(&.as_s)

    unless repository_url && tag_name
      return json({
        error: "Missing required fields",
      }, status: 400)
    end

    process_version(repository_url, tag_name)
  end

  private def process_version(repository_url : String, tag_name : String)
    # Normalize version (remove 'v' prefix if present)
    version = tag_name.starts_with?("v") ? tag_name[1..] : tag_name

    # Find shard by repository URL
    shard = ShardQuery.new
      .repository_url(repository_url)
      .first?

    unless shard
      return json({
        error: "Shard not found",
      }, status: 404)
    end

    # Check if version already exists
    existing_version = ShardVersionQuery.new
      .shard_id(shard.id)
      .version(version)
      .first?

    if existing_version
      return json({
        error: "Version already indexed",
      }, status: 422)
    end

    # Create the version first
    SaveShardVersion.create(
      shard_id: shard.id,
      version: version,
      released_at: Time.utc,
      yanked: false
    ) do |operation, shard_version|
      if shard_version
        # Enqueue indexing worker
        begin
          IndexShardWorker.enqueue(
            shard_name: shard.name,
            version: version
          )

          json({
            message: "Webhook processed successfully",
            action:  "indexed",
            shard:   shard.name,
            version: version,
          }, status: 200)
        rescue ex : Exception
          Log.error(exception: ex) { "Failed to enqueue IndexShardWorker" }
          json({
            error: "Failed to enqueue indexing job: #{ex.message}",
          }, status: 500)
        end
      else
        json({
          errors: operation.errors.map { |attr, msg| {attr.to_s, msg} },
        }, status: 422)
      end
    end
  end
end
