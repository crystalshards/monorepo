# Sets the Cloud Tasks variables for one example and puts the environment back.
#
# The production queue reads its configuration from the process environment and
# refuses to invent a default, so exercising that path at all means setting
# real values. Restoring them afterwards is not tidiness: a leaked
# DOCS_LAUNCHER_URL would make a later example think it is in a configured
# production process and assert against the wrong branch.
#
# A nil value means "unset this", which is how the "refuses to enqueue when
# unset" example is written without editing the process environment by hand.
private def apply_env(values : Hash(String, String?)) : Nil
  values.each do |key, value|
    if value
      ENV[key] = value
    else
      ENV.delete(key)
    end
  end
end

def with_cloud_tasks_env(
  project : String? = "test-project",
  queue : String? = "docs-builds",
  location : String? = "us-central1",
  launcher_url : String? = "https://docs-launcher.example.run.app",
  audience : String? = "https://docs-launcher.docs.example.internal",
  invoker : String? = "docs-tasks@example.iam.gserviceaccount.com",
  deadline : String? = nil,
  &
)
  desired = {
    CrystalDocs::CloudTasksConfig::PROJECT_ENV  => project,
    CrystalDocs::CloudTasksConfig::QUEUE_ENV    => queue,
    CrystalDocs::CloudTasksConfig::LOCATION_ENV => location,
    CrystalDocs::CloudTasksConfig::LAUNCHER_ENV => launcher_url,
    # Different from launcher_url on purpose. They were one value, which is why
    # the launcher could never be told what audience to expect, and a fixture
    # that made them equal would let them be conflated again silently.
    CrystalDocs::CloudTasksConfig::AUDIENCE_ENV => audience,
    CrystalDocs::CloudTasksConfig::INVOKER_ENV  => invoker,
    CrystalDocs::CloudTasksConfig::DEADLINE_ENV => deadline,
  } of String => String?

  previous = desired.keys.to_h { |key| {key, ENV[key]?} }

  # The restore is guarded from here rather than by an `ensure` on the whole
  # method: a local assigned in the body reads as nilable inside a method-level
  # ensure, and the restore must not be the thing that raises.
  apply_env(desired)

  begin
    yield
  ensure
    apply_env(previous)
  end
end
