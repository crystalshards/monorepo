# Sets the Cloud Tasks variables for one example and puts the environment back.
#
# The production queue reads its configuration from the process environment and
# refuses to invent a default, so exercising that path at all means setting
# real values. Restoring them afterwards is not tidiness: a leaked
# DOCS_LAUNCHER_URL would make a later example think it is in a configured
# production process and assert against the wrong branch.
#
# Passing nil for a key unsets it, which is how the "refuses to enqueue when
# unset" example is written without editing the process environment by hand.
def with_cloud_tasks_env(
  project : String? = "test-project",
  queue : String? = "docs-builds",
  location : String? = "us-central1",
  launcher_url : String? = "https://docs-launcher.example.run.app",
  invoker : String? = "docs-tasks@example.iam.gserviceaccount.com",
  &
)
  desired = {
    CrystalDocs::CloudTasksConfig::PROJECT_ENV  => project,
    CrystalDocs::CloudTasksConfig::QUEUE_ENV    => queue,
    CrystalDocs::CloudTasksConfig::LOCATION_ENV => location,
    CrystalDocs::CloudTasksConfig::LAUNCHER_ENV => launcher_url,
    CrystalDocs::CloudTasksConfig::INVOKER_ENV  => invoker,
  }

  previous = desired.keys.to_h { |key| {key, ENV[key]?} }

  desired.each do |key, value|
    value ? ENV[key] = value : ENV.delete(key)
  end

  yield
ensure
  previous.each do |key, value|
    value ? ENV[key] = value : ENV.delete(key)
  end
end
