require "openssl/hmac"

class Api::Webhooks::Github < ApiAction
  # Skip authentication for webhooks
  include Api::Auth::SkipRequireAuthToken

  post "/api/webhooks/github" do
    verify_github_signature!

    event = request.headers["X-GitHub-Event"]?
    payload = parse_payload

    case event
    when "release"
      handle_release_event(payload)
    when "push"
      handle_push_event(payload) if tag_push?(payload)
    else
      # Ignore other events
      Log.info { "Ignoring GitHub webhook event: #{event}" }
    end

    json({status: "ok", message: "Webhook received"})
  rescue ex : SignatureError
    Log.error(exception: ex) { "GitHub webhook signature verification failed" }
    json({error: "Invalid signature"}, status: 401)
  rescue ex : Exception
    Log.error(exception: ex) { "GitHub webhook processing failed" }
    json({status: "ok", message: "Webhook received"})
  end

  private def verify_github_signature!
    signature_header = request.headers["X-Hub-Signature-256"]?
    raise SignatureError.new("Missing signature") unless signature_header

    body = request.body.try(&.gets_to_end) || ""
    request.body.try(&.rewind)

    webhook_secret = ENV["GITHUB_WEBHOOK_SECRET"]? || raise SignatureError.new("Webhook secret not configured")
    expected = "sha256=" + OpenSSL::HMAC.hexdigest(:sha256, webhook_secret, body)

    unless secure_compare(expected, signature_header)
      raise SignatureError.new("Invalid signature")
    end
  end

  private def parse_payload : JSON::Any
    body = request.body.try(&.gets_to_end) || "{}"
    request.body.try(&.rewind)
    JSON.parse(body)
  end

  private def handle_release_event(payload : JSON::Any)
    action = payload["action"]?.try(&.as_s)
    return unless action == "published"

    tag_name = payload["release"]["tag_name"].as_s
    repo_full_name = payload["repository"]["full_name"].as_s
    repo_url = payload["repository"]["html_url"].as_s

    enqueue_indexing(repo_full_name, tag_name, repo_url)
  end

  private def handle_push_event(payload : JSON::Any)
    ref = payload["ref"].as_s
    tag_name = ref.sub("refs/tags/", "")
    repo_full_name = payload["repository"]["full_name"].as_s
    repo_url = payload["repository"]["html_url"].as_s

    enqueue_indexing(repo_full_name, tag_name, repo_url)
  end

  private def tag_push?(payload : JSON::Any) : Bool
    ref = payload["ref"]?.try(&.as_s)
    ref ? ref.starts_with?("refs/tags/") : false
  end

  private def enqueue_indexing(repo_full_name : String, tag_name : String, repo_url : String)
    # Extract shard name from repo (e.g., "owner/repo-name" -> "repo-name")
    shard_name = repo_full_name.split("/").last

    # Normalize version (remove 'v' prefix if present)
    version = tag_name.sub(/^v/, "")

    # Check if already indexed (idempotency)
    existing = check_existing_version(shard_name, version)

    if existing
      Log.info { "Shard version already indexed: #{shard_name}@#{version}" }
      return
    end

    # Enqueue worker
    IndexShardWorker.enqueue(
      shard_name: shard_name,
      version: version
    )

    Log.info { "Enqueued IndexShardWorker for #{shard_name}@#{version}" }
  end

  private def check_existing_version(shard_name : String, version : String) : ShardVersion?
    shard = ShardQuery.new.name(shard_name).first?
    return nil unless shard

    ShardVersionQuery.new
      .shard_id(shard.id.not_nil!)
      .version(version)
      .first?
  rescue ex : Exception
    Log.error(exception: ex) { "Error checking existing version for #{shard_name}@#{version}" }
    nil
  end

  # Constant-time comparison to prevent timing attacks
  private def secure_compare(a : String, b : String) : Bool
    return false unless a.bytesize == b.bytesize

    result = 0
    a.each_byte.zip(b.each_byte) do |byte_a, byte_b|
      result |= byte_a ^ byte_b
    end

    result == 0
  end

  class SignatureError < Exception
  end
end
