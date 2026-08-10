require "../../../spec_helper"
require "openssl/hmac"

def generate_signature(payload : String) : String
  secret = ENV["GITHUB_WEBHOOK_SECRET"]? || "test_webhook_secret_for_specs"
  "sha256=" + OpenSSL::HMAC.hexdigest(:sha256, secret, payload)
end

# GitHub sends the payload as a raw body and signs it, so the request has to be
# built with a verbatim body and real header names. Lucky's `exec` would JSON
# encode the whole named tuple instead, and its `headers` helper rewrites dashes
# to underscores, which is why this goes through `exec_raw` and `raw_headers`.
private def post_webhook(payload : String, event : String, signature : String? = nil)
  headers = {
    "X-GitHub-Event" => event,
    "Content-Type"   => "application/json",
  }

  if value = signature
    headers["X-Hub-Signature-256"] = value
  end

  ApiClient.new.raw_headers(headers).exec_raw(Api::Webhooks::Github, payload)
end

describe Api::Webhooks::Github do
  describe "POST /api/webhooks/github" do
    it "accepts valid release webhook with correct signature" do
      payload = {
        action:  "published",
        release: {
          tag_name: "v1.0.0",
          name:     "Release 1.0.0",
        },
        repository: {
          full_name: "user/test-shard",
          html_url:  "https://github.com/user/test-shard",
        },
      }.to_json

      response = post_webhook(payload, "release", generate_signature(payload))

      response.should send_json(200)
      json = JSON.parse(response.body)
      json["status"].should eq("ok")
      json["message"].should eq("Webhook received")
    end

    it "rejects webhook with invalid signature" do
      payload = {
        action:  "published",
        release: {tag_name: "v1.0.0"},
      }.to_json

      response = post_webhook(payload, "release", "sha256=invalid_signature")

      response.status_code.should eq(401)
    end

    it "rejects webhook with missing signature" do
      payload = {
        action:  "published",
        release: {tag_name: "v1.0.0"},
      }.to_json

      response = post_webhook(payload, "release")

      response.status_code.should eq(401)
    end

    it "rejects a signature computed over a different body" do
      payload = {action: "published", release: {tag_name: "v1.0.0"}}.to_json
      tampered = {action: "published", release: {tag_name: "v9.9.9"}}.to_json

      response = post_webhook(tampered, "release", generate_signature(payload))

      response.status_code.should eq(401)
    end

    it "handles tag push events" do
      payload = {
        ref:        "refs/tags/v2.0.0",
        repository: {
          full_name: "user/test-shard",
          html_url:  "https://github.com/user/test-shard",
        },
      }.to_json

      response = post_webhook(payload, "push", generate_signature(payload))

      response.should send_json(200)
    end

    it "ignores non-tag push events" do
      payload = {
        ref:        "refs/heads/main",
        repository: {
          full_name: "user/test-shard",
          html_url:  "https://github.com/user/test-shard",
        },
      }.to_json

      response = post_webhook(payload, "push", generate_signature(payload))

      response.should send_json(200)
    end

    it "ignores unknown event types" do
      payload = {action: "opened"}.to_json

      response = post_webhook(payload, "pull_request", generate_signature(payload))

      response.should send_json(200)
    end

    it "handles duplicate events (idempotency)" do
      shard = ShardFactory.create &.name("test-shard")
        .repository_url("https://github.com/user/test-shard")
      ShardVersionFactory.create &.shard_id(shard.id.not_nil!)
        .version("1.0.0")

      payload = {
        action:  "published",
        release: {
          tag_name: "v1.0.0",
          name:     "Release 1.0.0",
        },
        repository: {
          full_name: "user/test-shard",
          html_url:  "https://github.com/user/test-shard",
        },
      }.to_json

      response = post_webhook(payload, "release", generate_signature(payload))

      response.should send_json(200)
      # An already indexed version must not be duplicated by a replayed delivery.
      ShardVersionQuery.new.shard_id(shard.id).version("1.0.0").select_count.should eq(1)
    end

    it "normalizes version by removing 'v' prefix" do
      payload = {
        action:  "published",
        release: {
          tag_name: "v3.0.0",
          name:     "Release 3.0.0",
        },
        repository: {
          full_name: "user/new-shard",
          html_url:  "https://github.com/user/new-shard",
        },
      }.to_json

      response = post_webhook(payload, "release", generate_signature(payload))

      response.should send_json(200)
    end

    it "extracts shard name from repository full_name" do
      payload = {
        action:  "published",
        release: {
          tag_name: "v1.0.0",
          name:     "Release 1.0.0",
        },
        repository: {
          full_name: "someuser/my-awesome-shard",
          html_url:  "https://github.com/someuser/my-awesome-shard",
        },
      }.to_json

      response = post_webhook(payload, "release", generate_signature(payload))

      response.should send_json(200)
    end

    it "handles release events that are not 'published'" do
      payload = {
        action:     "created",
        release:    {tag_name: "v1.0.0"},
        repository: {
          full_name: "user/test-shard",
          html_url:  "https://github.com/user/test-shard",
        },
      }.to_json

      response = post_webhook(payload, "release", generate_signature(payload))

      response.should send_json(200)
    end

    it "creates the released version for a registered shard so indexing can run" do
      shard = ShardFactory.create &.name("indexable-shard")
        .repository_url("https://github.com/user/indexable-shard")

      payload = {
        action:     "published",
        release:    {tag_name: "v2.1.0"},
        repository: {
          full_name: "user/indexable-shard",
          html_url:  "https://github.com/user/indexable-shard",
        },
      }.to_json

      response = post_webhook(payload, "release", generate_signature(payload))

      response.should send_json(200)

      # IndexShardWorker looks the version up and gives up when it is absent,
      # so the webhook has to persist it before enqueueing the job.
      created = ShardVersionQuery.new
        .shard_id(shard.id.not_nil!)
        .version("2.1.0")
        .first?

      created.should_not be_nil
      created.not_nil!.yanked.should be_false
    end

    it "does not create versions for an unregistered shard" do
      payload = {
        action:     "published",
        release:    {tag_name: "v1.0.0"},
        repository: {
          full_name: "user/never-registered",
          html_url:  "https://github.com/user/never-registered",
        },
      }.to_json

      response = post_webhook(payload, "release", generate_signature(payload))

      response.should send_json(200)
      ShardQuery.new.name("never-registered").first?.should be_nil
    end
  end
end
