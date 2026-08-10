require "openssl/hmac"

class Api::Webhooks::Github < ApiAction
  # GitHub signs the webhook itself; there is no bearer token to check.
  include Api::Auth::SkipRequireAuthToken

  post "/api/webhooks/github" do
    # The body is read exactly once: an incoming request body is not
    # rewindable, so signature verification and payload parsing share it.
    raw_body = request.body.try(&.gets_to_end) || ""

    verify_github_signature!(raw_body)

    payload = JSON.parse(raw_body.presence || "{}")

    case request.headers["X-GitHub-Event"]?
    when "release"
      handle_release_event(payload)
    when "push"
      handle_push_event(payload) if tag_push?(payload)
    else
      Log.info { "Ignoring GitHub webhook event: #{request.headers["X-GitHub-Event"]?}" }
    end

    json({status: "ok", message: "Webhook received"})
  rescue ex : SignatureError
    Log.error(exception: ex) { "GitHub webhook signature verification failed" }
    json({error: "Invalid signature"}, status: 401)
  rescue ex : Exception
    # GitHub retries on non-2xx. A malformed payload is our problem to fix,
    # not something a retry will resolve, so acknowledge and log it.
    Log.error(exception: ex) { "GitHub webhook processing failed" }
    json({status: "ok", message: "Webhook received"})
  end

  private def verify_github_signature!(raw_body : String)
    signature_header = request.headers["X-Hub-Signature-256"]?
    raise SignatureError.new("Missing signature") unless signature_header

    webhook_secret = ENV["GITHUB_WEBHOOK_SECRET"]?
    raise SignatureError.new("Webhook secret not configured") unless webhook_secret

    expected = "sha256=" + OpenSSL::HMAC.hexdigest(:sha256, webhook_secret, raw_body)

    unless secure_compare(expected, signature_header)
      raise SignatureError.new("Invalid signature")
    end
  end

  private def handle_release_event(payload : JSON::Any)
    return unless payload["action"]?.try(&.as_s) == "published"

    enqueue_indexing(
      payload["repository"]["full_name"].as_s,
      payload["release"]["tag_name"].as_s
    )
  end

  private def handle_push_event(payload : JSON::Any)
    enqueue_indexing(
      payload["repository"]["full_name"].as_s,
      payload["ref"].as_s.sub("refs/tags/", "")
    )
  end

  private def tag_push?(payload : JSON::Any) : Bool
    !!payload["ref"]?.try(&.as_s.starts_with?("refs/tags/"))
  end

  private def enqueue_indexing(repo_full_name : String, tag_name : String)
    shard_name = repo_full_name.split("/").last
    version = tag_name.sub(/^v/, "")

    if already_indexed?(shard_name, version)
      Log.info { "Shard version already indexed: #{shard_name}@#{version}" }
      return
    end

    IndexShardWorker.enqueue(shard_name: shard_name, version: version)

    Log.info { "Enqueued IndexShardWorker for #{shard_name}@#{version}" }
  end

  private def already_indexed?(shard_name : String, version : String) : Bool
    shard = ShardQuery.new.name(shard_name).first?
    return false unless shard

    !ShardVersionQuery.new
      .shard_id(shard.id.not_nil!)
      .version(version)
      .first?
      .nil?
  end

  # Constant-time comparison to prevent timing attacks.
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
