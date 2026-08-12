require "http/client"
require "json"
require "../../../../services/docs_build_queue"

# The `docs-launcher` role: the only identity allowed to start a documentation
# build.
#
# A build compiles third party code, so it runs in a Cloud Run Job that holds
# no credentials whatsoever. That Job cannot fetch its own source or publish
# its own output, and deliberately cannot: it is handed one signed GET and one
# signed PUT, minted here, each good for a single object and expiring in
# minutes. This action is the trusted half. It clones, installs dependencies,
# starts the Job, validates what comes back, publishes it and records the
# outcome, because the build identity can do none of those things.
#
# It is reached only through Cloud Tasks. The queue holds this request open for
# the whole build, which is what lets an identity with database access write
# the result: nothing else in the system is both trusted and still running when
# a build finishes.
class Api::Internal::Docs::Build < ApiAction
  # The app's own bearer token is not the credential here. Cloud Tasks presents
  # a Google-signed OIDC token instead, and `verify_caller!` below is what
  # actually guards this route.
  include Api::Auth::SkipRequireAuthToken

  # This route is mounted on every revision built from this image, including
  # the public crystalshards service. That is safe because authorisation is
  # checked here rather than by the network, and it is worth stating plainly:
  # if this check is ever weakened, the weakening is reachable from the public
  # internet.
  class UnauthorizedCaller < Exception; end

  # Google's endpoint for validating an id token. Used rather than verifying
  # RS256 against a cached JWKS by hand, because a hand-rolled verifier that
  # forgets to check `aud`, or accepts `alg: none`, fails open and looks
  # identical to a working one. A build takes minutes, so one call costs
  # nothing measurable here.
  TOKENINFO = "https://oauth2.googleapis.com/tokeninfo"

  # Test seam. Given the raw bearer token, returns the verified claims. The
  # default reaches Google; a spec installs a fake to exercise the authorised
  # path without a network. The unauthorised paths never reach it.
  class_property verifier : Proc(String, JSON::Any) = ->(token : String) {
    Api::Internal::Docs::Build.fetch_claims(token)
  }

  post "/internal/docs/build" do
    verify_caller!

    task = CrystalShards::DocsBuildTask.from_json(request.body.try(&.gets_to_end) || "")

    Log.info { "Docs build #{task.build_id} starting for #{task.package_name}@#{task.version}" }

    # Synchronous on purpose. `perform` records success or failure against the
    # request row, and it is the last process in the chain that can: the Job
    # has no database credential. Returning early would leave every request
    # pending forever.
    BuildDocsWorker.new(shard_name: task.package_name, version: task.version).perform

    # A shard that does not compile is a finished build, not a failed
    # delivery. `perform` has already recorded the failure and the reader can
    # see it, so this acknowledges the task rather than asking Cloud Tasks to
    # run the same doomed build again.
    json({status: "ok", build_id: task.build_id})
  rescue ex : UnauthorizedCaller
    Log.warn { "Rejected an unauthenticated docs build request: #{ex.message}" }
    json({error: "Unauthorized"}, status: 401)
  rescue ex : JSON::Error
    # Malformed input is our bug or someone probing, and no retry fixes it.
    Log.error(exception: ex) { "Docs build request was not a build task" }
    json({error: "Bad Request"}, status: 400)
  rescue ex : Exception
    # Infrastructure failed rather than the shard. Cloud Tasks should try
    # again, so this is the one path that reports failure.
    Log.error(exception: ex) { "Docs build request failed" }
    json({error: "Build failed"}, status: 500)
  end

  # Three things must hold, and all three matter.
  private def verify_caller! : Nil
    header = request.headers["Authorization"]?
    raise UnauthorizedCaller.new("no Authorization header") if header.nil?

    unless header.starts_with?("Bearer ")
      raise UnauthorizedCaller.new("Authorization header is not a bearer token")
    end

    token = header[7..].strip
    raise UnauthorizedCaller.new("empty bearer token") if token.empty?

    claims =
      begin
        @@verifier.call(token)
      rescue ex : Exception
        raise UnauthorizedCaller.new("token could not be verified: #{ex.message}")
      end

    # The audience is what stops a token minted for some other Cloud Run
    # service, by some other caller, from opening this one. A valid Google
    # token is not by itself a token for us.
    audience = claims["aud"]?.try(&.as_s?)
    expected_audience = CrystalShards::CloudTasksConfig.fetch(CrystalShards::CloudTasksConfig::AUDIENCE_ENV)

    unless audience == expected_audience
      raise UnauthorizedCaller.new("token audience #{audience.inspect} is not this service")
    end

    # And the caller must be the one service account the queue acts as. Any
    # other verified Google identity, including a human with a valid id token,
    # is refused.
    email = claims["email"]?.try(&.as_s?)
    expected_email = CrystalShards::CloudTasksConfig.fetch(CrystalShards::CloudTasksConfig::INVOKER_ENV)

    unless email == expected_email
      raise UnauthorizedCaller.new("token subject #{email.inspect} is not the build invoker")
    end
  end

  protected def self.fetch_claims(token : String) : JSON::Any
    response = HTTP::Client.get("#{TOKENINFO}?id_token=#{URI.encode_www_form(token)}")

    raise "tokeninfo returned #{response.status_code}" unless response.success?

    JSON.parse(response.body)
  end
end
