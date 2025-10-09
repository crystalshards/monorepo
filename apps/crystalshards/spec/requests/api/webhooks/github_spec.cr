require "../../../spec_helper"
require "openssl/hmac"

# Helper method to generate valid HMAC signature
def generate_webhook_signature(payload : String) : String
  secret = ENV["GITHUB_WEBHOOK_SECRET"]? || "test_webhook_secret"
  hmac = OpenSSL::HMAC.hexdigest(OpenSSL::Algorithm::SHA256, secret, payload)
  "sha256=#{hmac}"
end

# Helper to send webhook requests with proper signature
def send_webhook(payload : String, event_type : String, signature : String? = nil)
  sig = signature || generate_webhook_signature(payload)

  client = ApiClient.new
  client.headers(
    "X-Hub-Signature-256": sig,
    "X-GitHub-Event": event_type,
    "Content-Type": "application/json"
  )
  client.exec_raw(Api::Webhooks::Github, body: payload)
end

describe Api::Webhooks::Github do
  describe "POST /api/webhooks/github" do
    it "processes valid release.published event" do
      shard = ShardFactory.create &.name("test-shard")
        .repository_url("https://github.com/testuser/test-shard")

      payload = {
        action:  "published",
        release: {
          tag_name: "v1.0.0",
        },
        repository: {
          full_name: "testuser/test-shard",
          html_url:  "https://github.com/testuser/test-shard",
        },
      }.to_json

      response = send_webhook(payload, "release")

      response.should send_json(200)
      json = JSON.parse(response.body)
      json["message"].should eq("Webhook processed successfully")
      json["action"].should eq("indexed")
    end

    it "processes valid release.created event" do
      shard = ShardFactory.create &.name("test-shard")
        .repository_url("https://github.com/testuser/test-shard")

      payload = {
        action:  "created",
        release: {
          tag_name: "v0.2.0",
        },
        repository: {
          full_name: "testuser/test-shard",
          html_url:  "https://github.com/testuser/test-shard",
        },
      }.to_json

      response = send_webhook(payload, "release")

      response.should send_json(200)
    end

    it "processes valid create tag event" do
      shard = ShardFactory.create &.name("test-shard")
        .repository_url("https://github.com/testuser/test-shard")

      payload = {
        ref:        "v2.0.0",
        ref_type:   "tag",
        repository: {
          full_name: "testuser/test-shard",
          html_url:  "https://github.com/testuser/test-shard",
        },
      }.to_json

      response = send_webhook(payload, "create")

      response.should send_json(200)
    end

    it "rejects invalid signature" do
      payload = {
        action:  "published",
        release: {
          tag_name: "v1.0.0",
        },
        repository: {
          full_name: "testuser/test-shard",
        },
      }.to_json

      response = send_webhook(payload, "release", signature: "sha256=invalid_signature")

      response.should send_json(400)
      json = JSON.parse(response.body)
      json["error"].should eq("Invalid signature")
    end

    it "rejects missing signature" do
      payload = {
        action:  "published",
        release: {
          tag_name: "v1.0.0",
        },
      }.to_json

      # Send without signature header
      client = ApiClient.new
      client.headers(
        "X-GitHub-Event": "release",
        "Content-Type": "application/json"
      )
      response = client.exec_raw(Api::Webhooks::Github, body: payload)

      response.should send_json(400)
      json = JSON.parse(response.body)
      json["error"].should eq("Missing signature")
    end

    it "returns 404 when shard not found" do
      payload = {
        action:  "published",
        release: {
          tag_name: "v1.0.0",
        },
        repository: {
          full_name: "nonexistent/shard",
          html_url:  "https://github.com/nonexistent/shard",
        },
      }.to_json

      response = send_webhook(payload, "release")

      response.should send_json(404)
      json = JSON.parse(response.body)
      json["error"].should eq("Shard not found")
    end

    it "returns 422 when version already indexed" do
      shard = ShardFactory.create &.name("test-shard")
        .repository_url("https://github.com/testuser/test-shard")

      # Create existing version
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")

      payload = {
        action:  "published",
        release: {
          tag_name: "v1.0.0",
        },
        repository: {
          full_name: "testuser/test-shard",
          html_url:  "https://github.com/testuser/test-shard",
        },
      }.to_json

      response = send_webhook(payload, "release")

      response.should send_json(422)
      json = JSON.parse(response.body)
      json["error"].should eq("Version already indexed")
    end

    it "handles non-tag create events" do
      payload = {
        ref:        "main",
        ref_type:   "branch",
        repository: {
          full_name: "testuser/test-shard",
        },
      }.to_json

      response = send_webhook(payload, "create")

      response.should send_json(422)
      json = JSON.parse(response.body)
      json["error"].should eq("Not a relevant event")
    end

    it "handles irrelevant release actions" do
      payload = {
        action:  "edited",
        release: {
          tag_name: "v1.0.0",
        },
        repository: {
          full_name: "testuser/test-shard",
        },
      }.to_json

      response = send_webhook(payload, "release")

      response.should send_json(422)
      json = JSON.parse(response.body)
      json["error"].should eq("Not a relevant event")
    end

    it "normalizes version tags correctly" do
      shard = ShardFactory.create &.name("test-shard")
        .repository_url("https://github.com/testuser/test-shard")

      payload = {
        action:  "published",
        release: {
          tag_name: "v1.2.3", # With 'v' prefix
        },
        repository: {
          full_name: "testuser/test-shard",
          html_url:  "https://github.com/testuser/test-shard",
        },
      }.to_json

      response = send_webhook(payload, "release")

      response.should send_json(200)
      # Verify the version was normalized (should be "1.2.3" without 'v')
    end
  end
end
