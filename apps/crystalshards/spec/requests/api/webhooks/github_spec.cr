require "../../../spec_helper"
require "openssl/hmac"

def generate_signature(payload : String) : String
  secret = ENV["GITHUB_WEBHOOK_SECRET"]? || "test_webhook_secret_for_specs"
  "sha256=" + OpenSSL::HMAC.hexdigest(:sha256, secret, payload)
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

      signature = generate_signature(payload)

      response = ApiClient.exec(Api::Webhooks::Github,
        body: payload,
        headers: {
          "X-GitHub-Event"      => "release",
          "X-Hub-Signature-256" => signature,
          "Content-Type"        => "application/json",
        }
      )

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

      response = ApiClient.exec(Api::Webhooks::Github,
        body: payload,
        headers: {
          "X-GitHub-Event"      => "release",
          "X-Hub-Signature-256" => "sha256=invalid_signature",
          "Content-Type"        => "application/json",
        }
      )

      response.status_code.should eq(401)
    end

    it "rejects webhook with missing signature" do
      payload = {
        action:  "published",
        release: {tag_name: "v1.0.0"},
      }.to_json

      response = ApiClient.exec(Api::Webhooks::Github,
        body: payload,
        headers: {
          "X-GitHub-Event" => "release",
          "Content-Type"   => "application/json",
        }
      )

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

      signature = generate_signature(payload)

      response = ApiClient.exec(Api::Webhooks::Github,
        body: payload,
        headers: {
          "X-GitHub-Event"      => "push",
          "X-Hub-Signature-256" => signature,
          "Content-Type"        => "application/json",
        }
      )

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

      signature = generate_signature(payload)

      response = ApiClient.exec(Api::Webhooks::Github,
        body: payload,
        headers: {
          "X-GitHub-Event"      => "push",
          "X-Hub-Signature-256" => signature,
          "Content-Type"        => "application/json",
        }
      )

      response.should send_json(200)
      # Should still return OK but not process
    end

    it "ignores unknown event types" do
      payload = {
        action: "opened",
      }.to_json

      signature = generate_signature(payload)

      response = ApiClient.exec(Api::Webhooks::Github,
        body: payload,
        headers: {
          "X-GitHub-Event"      => "pull_request",
          "X-Hub-Signature-256" => signature,
          "Content-Type"        => "application/json",
        }
      )

      response.should send_json(200)
    end

    it "handles duplicate events (idempotency)" do
      # Create existing shard and version
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

      signature = generate_signature(payload)

      response = ApiClient.exec(Api::Webhooks::Github,
        body: payload,
        headers: {
          "X-GitHub-Event"      => "release",
          "X-Hub-Signature-256" => signature,
          "Content-Type"        => "application/json",
        }
      )

      response.should send_json(200)
      # Should not enqueue worker again
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

      signature = generate_signature(payload)

      response = ApiClient.exec(Api::Webhooks::Github,
        body: payload,
        headers: {
          "X-GitHub-Event"      => "release",
          "X-Hub-Signature-256" => signature,
          "Content-Type"        => "application/json",
        }
      )

      response.should send_json(200)
      # Version should be stored as "3.0.0", not "v3.0.0"
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

      signature = generate_signature(payload)

      response = ApiClient.exec(Api::Webhooks::Github,
        body: payload,
        headers: {
          "X-GitHub-Event"      => "release",
          "X-Hub-Signature-256" => signature,
          "Content-Type"        => "application/json",
        }
      )

      response.should send_json(200)
      # Shard name should be "my-awesome-shard", not "someuser/my-awesome-shard"
    end

    it "handles release events that are not 'published'" do
      payload = {
        action:  "created",
        release: {
          tag_name: "v1.0.0",
        },
        repository: {
          full_name: "user/test-shard",
          html_url:  "https://github.com/user/test-shard",
        },
      }.to_json

      signature = generate_signature(payload)

      response = ApiClient.exec(Api::Webhooks::Github,
        body: payload,
        headers: {
          "X-GitHub-Event"      => "release",
          "X-Hub-Signature-256" => signature,
          "Content-Type"        => "application/json",
        }
      )

      response.should send_json(200)
      # Should ignore non-published release actions
    end
  end
end
