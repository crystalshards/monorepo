ENV["LUCKY_ENV"] = "test"
ENV["DEV_PORT"] = "5005"

require "spec"

# The fake runner binds and publishes RUNNER_URL BEFORE the app's config
# loads, because config/runner.cr reads the variable at require time. A fake
# started after the require would be announcing a URL nobody consumed.
require "./support/fake_runner"
FakeRunner.start

require "../src/app"
require "./support/api_client"
require "./support/browser_client"

include Lucky::RequestExpectations

Habitat.raise_if_missing_settings!
