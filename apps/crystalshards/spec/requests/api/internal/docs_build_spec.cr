require "../../../spec_helper"

# This route starts a documentation build, which means minting signed
# object-storage URLs and compiling third party code. It is mounted on every
# revision built from this image, including the public crystalshards service,
# so the check it performs is the only thing between the internet and a build.
#
# Every example here is offline. The rejection paths must not need a network
# call to say no, and that is half the point: a verifier that has to reach
# Google before it can refuse would turn an outage into an open door.
private def post_build(token : String? = nil)
  headers = {"Content-Type" => "application/json"}
  headers["Authorization"] = token if token

  body = {package_name: "kemal", version: "1.6.0", build_id: "build-1"}.to_json

  ApiClient.new(skip_default_headers: true)
    .raw_headers(headers)
    .exec_raw(Api::Internal::Docs::Build, body)
end

# Swaps the token verifier for one that returns fixed claims, and always puts
# the real one back.
private def with_claims(claims, &)
  original = Api::Internal::Docs::Build.verifier

  Api::Internal::Docs::Build.verifier = ->(_token : String) : JSON::Any {
    JSON.parse(claims.to_json)
  }

  begin
    yield
  ensure
    Api::Internal::Docs::Build.verifier = original
  end
end

describe Api::Internal::Docs::Build do
  describe "an unauthenticated caller" do
    it "is refused when it presents no credential at all" do
      post_build.status_code.should eq(401)
    end

    it "is refused when the Authorization header is not a bearer token" do
      post_build("Basic aGk6dGhlcmU=").status_code.should eq(401)
    end

    it "is refused when the bearer token is empty rather than treated as absent" do
      post_build("Bearer    ").status_code.should eq(401)
    end

    # The app's own API token is a valid credential for the rest of the API and
    # must not open this door.
    it "is refused when the token does not verify as a Google identity" do
      original = Api::Internal::Docs::Build.verifier

      Api::Internal::Docs::Build.verifier = ->(_token : String) : JSON::Any {
        raise "not a google id token"
      }

      begin
        post_build("Bearer an-app-api-token").status_code.should eq(401)
      ensure
        Api::Internal::Docs::Build.verifier = original
      end
    end

    # Refusing must not depend on the build pipeline being wired up, or a
    # misconfigured launcher would start answering 500 instead of 401 and the
    # difference would be invisible from outside.
    it "is refused before anything reaches the build pipeline" do
      builder = CrystalShards::MockDocsBuilder.new
      storage = CrystalShards::MockStorageService.new

      WorkerSeams.with_docs_pipeline(builder, storage) do
        post_build.status_code.should eq(401)
      end

      builder.calls.should be_empty
    end
  end

  describe "a verified caller that is not the build invoker" do
    # A real, Google-signed token minted for some other Cloud Run service.
    # Verifying the signature is not enough: the audience is what makes a
    # token a token for us.
    it "is refused when the token was minted for a different audience" do
      with_claims({
        aud:   "https://some-other-service.run.app",
        email: "docs-tasks@example.iam.gserviceaccount.com",
      }) do
        with_cloud_tasks_env do
          post_build("Bearer valid-but-not-for-us").status_code.should eq(401)
        end
      end
    end

    # Right audience, wrong principal. Any Google identity can obtain a token
    # for a known audience, so the caller must also be the one service account
    # the queue acts as.
    it "is refused when the subject is not the build invoker" do
      with_claims({
        aud:   "https://docs-launcher.example.run.app",
        email: "someone-else@example.iam.gserviceaccount.com",
      }) do
        with_cloud_tasks_env do
          post_build("Bearer valid-wrong-principal").status_code.should eq(401)
        end
      end
    end
  end

  # The positive case, so the refusals above are proved to be the check working
  # rather than the route being broken for everyone.
  describe "the build invoker" do
    it "is accepted and the build runs" do
      shard = ShardFactory.create &.name("kemal")
      ShardVersionFactory.create &.shard_id(shard.id).version("1.6.0")

      builder = CrystalShards::MockDocsBuilder.new
      storage = CrystalShards::MockStorageService.new

      with_claims({
        aud:   "https://docs-launcher.example.run.app",
        email: "docs-tasks@example.iam.gserviceaccount.com",
      }) do
        with_cloud_tasks_env do
          WorkerSeams.with_docs_pipeline(builder, storage) do
            response = post_build("Bearer the-real-thing")

            response.status_code.should eq(200)
            JSON.parse(response.body)["build_id"].as_s.should eq("build-1")
          end
        end
      end

      builder.calls.size.should eq(1)
    end
  end
end
