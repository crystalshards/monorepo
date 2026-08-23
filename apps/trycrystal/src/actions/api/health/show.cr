# The endpoint the deploy workflow's startup probe and smoke test poll.
#
# Deliberately does NOT probe the sandbox. If /api/health gated on the
# runner answering, a runner outage would keep this app's revisions from
# ever reaching Ready, and the honest failure mode for "sandbox down" is a
# console that serves the page and says so in character, not a website that
# vanishes. "configured" states exactly what it proves: the revision was
# given a RUNNER_URL. Whether the sandbox answers is reported per
# submission, where it belongs.
class Api::Health::Show < ApiAction
  get "/api/health" do
    json({
      status:    "ok",
      version:   "0.1.0",
      timestamp: Time.utc.to_rfc3339,
      services:  {
        runner: RunnerClient.settings.url.blank? ? "unconfigured" : "configured",
      },
    })
  end
end
