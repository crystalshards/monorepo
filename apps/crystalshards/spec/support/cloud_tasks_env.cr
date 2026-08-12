# Sets the Cloud Tasks variables for one example and puts the environment back.
#
# The production queue and the launcher's audience check both read the process
# environment and refuse to invent a default, so exercising either at all means
# setting real values. Restoring them afterwards is not tidiness: a leaked
# DOCS_LAUNCHER_URL would make a later example think it is in a configured
# production process and assert against the wrong branch.
#
# A nil value means "unset this", which is how a "refuses when unset" example
# is written without editing the process environment by hand.
private def apply_env(values : Hash(String, String?)) : Nil
  values.each do |key, value|
    if value
      ENV[key] = value
    else
      ENV.delete(key)
    end
  end
end

# Sets one environment variable for the duration of a block and restores it.
#
# Same reasoning as with_cloud_tasks_env: a leaked value makes a later example
# assert against a configuration it did not choose.
def with_env(key : String, value : String?, &)
  previous = ENV[key]?
  apply_env({key => value})

  begin
    yield
  ensure
    apply_env({key => previous})
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
    CrystalShards::CloudTasksConfig::PROJECT_ENV  => project,
    CrystalShards::CloudTasksConfig::QUEUE_ENV    => queue,
    CrystalShards::CloudTasksConfig::LOCATION_ENV => location,
    CrystalShards::CloudTasksConfig::LAUNCHER_ENV => launcher_url,
    # Deliberately different from launcher_url in the default, because they
    # were one value and that is exactly what broke: the launcher could not be
    # told an audience without terraform consuming its own output. A default
    # that made them equal would let a spec pass while the two were conflated
    # again.
    CrystalShards::CloudTasksConfig::AUDIENCE_ENV => audience,
    CrystalShards::CloudTasksConfig::INVOKER_ENV  => invoker,
    CrystalShards::CloudTasksConfig::DEADLINE_ENV => deadline,
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
