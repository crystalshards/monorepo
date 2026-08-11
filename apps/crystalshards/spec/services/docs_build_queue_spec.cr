require "../spec_helper"

# crystalshards is the second producer on the docs build queue. crystaldocs is
# the first, and both must build the same task for the same launcher route.
#
# The two producers live in separate binaries that never compile together, so
# nothing but these examples stops them drifting apart. Drift here is silent:
# a task with the wrong path is a 404 the launcher never sees, and a task with
# no OIDC block is a 403, and both look identical from a docs page, which is
# "the build never started" with nothing in either app's logs.
#
# Every example is offline.
describe CrystalShards::CloudTasksDocsBuildQueue do
  task = CrystalShards::DocsBuildTask.new("github.com/kemalcr/kemal", "1.6.0", "build-7")

  request = -> do
    JSON.parse(
      CrystalShards::CloudTasksDocsBuildQueue.task_json(
        "https://docs-launcher.example.run.app",
        "docs-tasks@example.iam.gserviceaccount.com",
        task
      )
    )["task"]
  end

  # The strongest available check on the path: not that it equals a string
  # typed twice, but that it equals the route the launcher action actually
  # mounts. If someone moves the action, this fails rather than production.
  it "targets the route the launcher really mounts" do
    CrystalShards::DocsBuildQueue::PATH.should eq(Api::Internal::Docs::Build.path)
  end

  it "posts to that route on the launcher" do
    request.call["httpRequest"]["httpMethod"].as_s.should eq("POST")
    request.call["httpRequest"]["url"].as_s
      .should eq("https://docs-launcher.example.run.app/internal/docs/build")
  end

  # The launcher parses these three field names. crystaldocs sends the same
  # three, and calls the first one package_name too even though this app calls
  # the value a shard name, because the wire format is the contract.
  it "carries package, version and build id as the launcher reads them" do
    decoded = JSON.parse(Base64.decode_string(request.call["httpRequest"]["body"].as_s))

    decoded["package_name"].as_s.should eq("github.com/kemalcr/kemal")
    decoded["version"].as_s.should eq("1.6.0")
    decoded["build_id"].as_s.should eq("build-7")
  end

  # Not optional: docs-launcher grants run.invoker to one service account, so a
  # task without a token is a 403 on every dispatch.
  it "signs the task as the invoker, for the launcher's own audience" do
    oidc = request.call["httpRequest"]["oidcToken"]

    oidc["serviceAccountEmail"].as_s.should eq("docs-tasks@example.iam.gserviceaccount.com")
    oidc["audience"].as_s.should eq("https://docs-launcher.example.run.app")
  end

  # Must equal the docs-launcher Cloud Run request timeout. Unset it defaults
  # to 600s and the launcher holds the request open for the whole build.
  #
  # The value is no longer a constant in this file. Two numbers that had to be
  # equal used to live in two places with nothing able to fail when they
  # drifted, so terraform now derives the service timeout and the env var from
  # one local and this reads the env var. The default argument is what
  # production uses; passing it explicitly is how the shape gets asserted
  # without a production environment.
  it "gives the launcher the whole build to answer in" do
    request.call["dispatchDeadline"].as_s.should eq("1800s")
  end

  # Proves the deadline is genuinely read from the deployment rather than
  # baked in. This calls task_json WITHOUT passing the deadline, so it goes
  # through CloudTasksConfig.deadline_seconds and the env var, which is the
  # path production uses. Passing the argument explicitly would prove nothing:
  # the spec would still pass if the env var were ignored entirely.
  #
  # 1200 rather than 3600 because Cloud Tasks caps an HTTP target's dispatch
  # deadline at 1800s, so 3600 would assert a payload the queue rejects.
  it "reads the deadline the deployment configured rather than a baked-in one" do
    with_cloud_tasks_env(deadline: "1200") do
      parsed = JSON.parse(
        CrystalShards::CloudTasksDocsBuildQueue.task_json(
          "https://docs-launcher.example.run.app",
          "docs-tasks@example.iam.gserviceaccount.com",
          task
        )
      )

      parsed["task"]["dispatchDeadline"].as_s.should eq("1200s")
    end
  end

  # The sandbox must finish before the launcher's deadline, or the launcher is
  # killed mid-wait and never records the outcome: the row stays `building`
  # forever with no failed_at, so the retry floor never reconsiders it and no
  # log says why. Terraform derives both from one variable with an explicit
  # margin, and this proves the app refuses if that ever stops holding.
  #
  # Exercised in both directions deliberately. A guard only ever observed
  # passing is not a guard.
  describe "sandbox and launcher timeout ordering" do
    it "accepts a sandbox that finishes comfortably before the deadline" do
      with_cloud_tasks_env(deadline: "1800") do
        with_env(CrystalShards::DocsSandbox::TIMEOUT_ENV, "1500") do
          CrystalShards::DocsSandbox.timeout_seconds.should eq(1500)
        end
      end
    end

    it "refuses a sandbox allowed to run right up to the deadline" do
      with_cloud_tasks_env(deadline: "1800") do
        with_env(CrystalShards::DocsSandbox::TIMEOUT_ENV, "1800") do
          expect_raises(CrystalShards::DocsSandbox::TimeoutOrdering, /must finish at least 300s before/) do
            CrystalShards::DocsSandbox.timeout_seconds
          end
        end
      end
    end

    # The boundary itself, so the comparison is proved to be the stated one
    # rather than off by the margin in either direction.
    it "refuses a sandbox that leaves less than the margin" do
      with_cloud_tasks_env(deadline: "1800") do
        with_env(CrystalShards::DocsSandbox::TIMEOUT_ENV, "1501") do
          expect_raises(CrystalShards::DocsSandbox::TimeoutOrdering) do
            CrystalShards::DocsSandbox.timeout_seconds
          end
        end
      end
    end
  end

  # Out of range must be refused where the message can name the variable.
  # Cloud Tasks would otherwise reject the CreateTask call, which enqueue
  # catches and logs as an unreachable queue, so every build would silently
  # fail to be commissioned with nothing pointing at the real cause.
  describe "deadline validation" do
    it "refuses a deadline above the Cloud Tasks ceiling" do
      with_cloud_tasks_env(deadline: "3600") do
        expect_raises(CrystalShards::CloudTasksConfig::InvalidDeadline, /between 15 and 1800/) do
          CrystalShards::CloudTasksConfig.deadline_seconds
        end
      end
    end

    it "refuses a non-numeric deadline rather than silently defaulting" do
      with_cloud_tasks_env(deadline: "half an hour") do
        expect_raises(CrystalShards::CloudTasksConfig::InvalidDeadline) do
          CrystalShards::CloudTasksConfig.deadline_seconds
        end
      end
    end

    # The development fallback is what keeps local dev and the suite working
    # with no cloud configuration at all.
    it "uses the development fallback outside production" do
      with_cloud_tasks_env(deadline: nil) do
        CrystalShards::CloudTasksConfig.deadline_seconds.should eq(1800)
      end
    end
  end

  describe "#enqueue" do
    it "sends one task to the configured queue and returns the build id" do
      sent = [] of {String, String}
      original = CrystalShards::CloudTasksDocsBuildQueue.transport

      CrystalShards::CloudTasksDocsBuildQueue.transport = ->(queue_path : String, task_json : String) {
        sent << {queue_path, task_json}
        nil
      }

      begin
        with_cloud_tasks_env do
          build_id = CrystalShards::CloudTasksDocsBuildQueue.new.enqueue("kemal", "1.6.0")

          sent.size.should eq(1)
          sent.first[0].should eq("projects/test-project/locations/us-central1/queues/docs-builds")

          decoded = JSON.parse(
            Base64.decode_string(JSON.parse(sent.first[1])["task"]["httpRequest"]["body"].as_s)
          )

          decoded["build_id"].as_s.should eq(build_id)
        end
      ensure
        CrystalShards::CloudTasksDocsBuildQueue.transport = original
      end
    end

    # Indexing a version is worth keeping even when the docs build could not be
    # commissioned: crystaldocs asks for the build itself the first time a
    # reader opens the page.
    it "returns nil rather than raising when the queue cannot be reached" do
      original = CrystalShards::CloudTasksDocsBuildQueue.transport

      CrystalShards::CloudTasksDocsBuildQueue.transport = ->(_q : String, _t : String) {
        raise "Cloud Tasks is unreachable"
      }

      begin
        with_cloud_tasks_env do
          CrystalShards::CloudTasksDocsBuildQueue.new.enqueue("kemal", "1.6.0").should be_nil
        end
      ensure
        CrystalShards::CloudTasksDocsBuildQueue.transport = original
      end
    end

    # Missing configuration must not be papered over with a default: a wrong
    # queue silently drops every build.
    it "refuses to enqueue when the launcher url is unset" do
      original = CrystalShards::CloudTasksDocsBuildQueue.transport
      sent = 0

      CrystalShards::CloudTasksDocsBuildQueue.transport = ->(_q : String, _t : String) {
        sent += 1
        nil
      }

      begin
        with_cloud_tasks_env(launcher_url: nil) do
          CrystalShards::CloudTasksDocsBuildQueue.new.enqueue("kemal", "1.6.0").should be_nil
        end

        sent.should eq(0)
      ensure
        CrystalShards::CloudTasksDocsBuildQueue.transport = original
      end
    end
  end
end

describe CrystalShards::DocsBuildQueue do
  it "uses the in-process queue outside production, so local dev needs no cloud" do
    CrystalShards::DocsBuildQueue.override = nil

    CrystalShards::DocsBuildQueue.build.should be_a(CrystalShards::InProcessDocsBuildQueue)
  end
end

# The dispatch seam itself: which jobs run where.
describe CrystalShards::InlineJobQueue do
  # Indexing and dependency work is database plus one read from the shard's
  # host. It runs where it was asked for because Cloud Run gives a container no
  # CPU after its response is written, so anything deferred without a durable
  # queue behind it is simply dropped.
  #
  # Proven with a shard the registry cannot resolve, so the worker takes its
  # early return and the example needs no git host. The assertion is that the
  # call reached the worker and completed here, rather than being handed to
  # something that would run it later.
  it "runs indexing inline rather than deferring it" do
    CrystalShards::JobQueue.override = nil

    WorkerSeams.capturing_followups do |followups|
      CrystalShards::InlineJobQueue.new.index_shard("no-such-shard", "1.0.0")

      followups.should be_empty
    end
  end

  # The one job that never runs where it was asked for.
  it "hands documentation builds to the queue rather than compiling here" do
    CrystalShards::DocsBuildQueue.override = nil

    CrystalShards::InlineJobQueue.new.build_docs("kemal", "1.6.0").should_not be_nil
  end
end
