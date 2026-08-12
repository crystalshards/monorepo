require "base64"
require "http/client"
require "json"
require "uuid"
require "./google_metadata"

module CrystalDocs
  # Producer side of the documentation build queue.
  #
  # This app never builds documentation and must not be able to. A build
  # compiles third party code, and Crystal expands macros while compiling, so
  # a shard can run commands during its own doc build. This process renders web
  # pages and holds the database credential, so the compile happens in a Cloud
  # Run Job (`docs-build`) that holds no credentials at all.
  #
  # Nor does this app start that Job. Starting one means minting signed
  # object-storage URLs, and only the `docs-launcher` service holds that
  # authority. A request travels:
  #
  #   crystaldocs -> Cloud Task -> docs-launcher -> docs-build execution
  #
  # Cloud Tasks rather than a direct HTTP call to the launcher, because the
  # request has to outlive this process. Cloud Run reclaims CPU once a response
  # is written and scales to zero, so a fire-and-forget call started while
  # rendering a docs page is cancelled before it lands. A task is durable, is
  # retried by Google, and its dispatch deadline is what bounds a build.
  abstract class DocsBuildQueue
    # The launcher route a task targets. crystalshards mounts this path; if
    # either side renames it, every dispatch 404s and builds stop silently.
    PATH = "/internal/docs/build"

    class_property override : DocsBuildQueue? = nil

    def self.build : DocsBuildQueue
      if installed = @@override
        return installed
      end

      # Development and test never reach Google. A contributor with no cloud
      # access has to be able to run the app and the suite, so the fallback is
      # in-process rather than a client that fails at boot.
      LuckyEnv.production? ? CloudTasksDocsBuildQueue.new : InProcessDocsBuildQueue.new
    end

    # Returns the build id, or nil when the request was never delivered. Nil is
    # not a failed build; it means nobody was told to build. The row stays
    # pending and the caller decides what to show the reader.
    abstract def enqueue(package_name : String, version : String) : String?
  end

  # The task body: everything the launcher needs, and nothing it has to infer.
  #
  # build_id is generated here rather than by the launcher so that the id
  # recorded against the request row is the same id the launcher logs. Without
  # it, a stuck build can only be traced by guessing from timestamps.
  struct DocsBuildTask
    include JSON::Serializable

    getter package_name : String
    getter version : String
    getter build_id : String

    def initialize(@package_name : String, @version : String, @build_id : String)
    end
  end

  # Production configuration. Every value is required and none is defaulted:
  # a wrong queue or a wrong audience fails as a 403 on a page nobody is
  # watching, so it is refused at first use with the variable named instead.
  module CloudTasksConfig
    PROJECT_ENV  = "GOOGLE_CLOUD_PROJECT"
    QUEUE_ENV    = "DOCS_BUILD_QUEUE"
    LOCATION_ENV = "DOCS_BUILD_QUEUE_LOCATION"
    LAUNCHER_ENV = "DOCS_LAUNCHER_URL"
    INVOKER_ENV  = "DOCS_TASKS_SERVICE_ACCOUNT"
    DEADLINE_ENV = "DOCS_BUILD_DEADLINE_SECONDS"

    # The OIDC audience, deliberately separate from the launcher's URL.
    #
    # They were one value, and that made docs-launcher unable to verify its own
    # callers: the audience has to be known by the enqueuer minting the token
    # and by the launcher checking it, and the launcher's URL is an output of
    # the launcher's own terraform resource. It was therefore never set there,
    # its check raised on every dispatch, every delivery returned 500, and no
    # documentation was ever built. This app is the primary enqueuer, so it is
    # the one whose tasks were failing.
    #
    # Mirrored from CrystalShards::CloudTasksConfig, like CrystalStorage::Keys,
    # because the two apps have to spell the same contract the same way.
    AUDIENCE_ENV = "DOCS_LAUNCHER_AUDIENCE"

    # Only used outside production. In production the deadline is required,
    # because it has to equal the docs-launcher Cloud Run request timeout and
    # terraform derives both from one value. Defaulting here would recreate
    # the second source of truth this variable exists to remove.
    DEFAULT_DEADLINE_SECONDS = 1800

    class Missing < Exception
      def initialize(key : String)
        super(<<-MESSAGE)
        #{key} is not set.

        Documentation builds are commissioned through Cloud Tasks, and this
        app will not enqueue one without knowing where to send it. Production
        requires all of:

          #{PROJECT_ENV}, #{QUEUE_ENV}, #{LOCATION_ENV}, #{LAUNCHER_ENV}, #{AUDIENCE_ENV}, #{INVOKER_ENV}, #{DEADLINE_ENV}

        In development and test the queue is in-process and none of these are
        read.
        MESSAGE
      end
    end

    def self.fetch(key : String) : String
      value = ENV[key]?
      raise Missing.new(key) if value.nil? || value.blank?
      value
    end

    # Cloud Tasks addresses a queue by full resource name. Composed here from
    # the three parts the deployment sets, so no one has to hand-type a path
    # that only fails at dispatch time.
    def self.queue_path : String
      "projects/#{fetch(PROJECT_ENV)}/locations/#{fetch(LOCATION_ENV)}/queues/#{fetch(QUEUE_ENV)}"
    end

    # Cloud Tasks accepts a dispatch deadline only within [15s, 1800s] for an
    # HTTP target. 1800 is therefore the ceiling, not merely the value we
    # picked, and the docs-launcher Cloud Run request timeout is pinned to the
    # same number because it is the largest the queue will honour.
    MIN_DEADLINE_SECONDS =   15
    MAX_DEADLINE_SECONDS = 1800

    class InvalidDeadline < Exception
      def initialize(raw : String)
        super(
          "#{DEADLINE_ENV} is #{raw.inspect}, which Cloud Tasks will not accept. " \
          "An HTTP target dispatch deadline must be a whole number of seconds " \
          "between #{MIN_DEADLINE_SECONDS} and #{MAX_DEADLINE_SECONDS}."
        )
      end
    end

    # How long the launcher may take before Cloud Tasks gives up on one
    # delivery.
    #
    # This must equal the docs-launcher Cloud Run request timeout, because the
    # launcher holds the request open for the whole build: it is the only
    # party in the chain that can write the outcome to the database. Two
    # numbers that must be equal used to live in two places, and nothing could
    # fail when they drifted. A wrong value passes every gate in the pipeline,
    # because /api/health answers in milliseconds, and shows up only as builds
    # dying mid-compile and being redelivered forever behind a green deploy.
    #
    # So terraform derives the service timeout and this variable from one
    # local, and this reads that variable rather than carrying its own copy.
    # Cloud Run env values are strings, hence the parse.
    #
    # Out of range is refused here rather than at dispatch. Cloud Tasks would
    # reject the CreateTask call, which this class catches and logs as "queue
    # unreachable", so every build would silently fail to be commissioned and
    # the cause would not appear in the message.
    # Production requires it; elsewhere an unset value falls back so local dev
    # and the suite need no cloud configuration. But a value that IS set is
    # always honoured and always validated, in every environment, so a bad
    # deadline is caught in CI rather than only once it reaches production.
    def self.deadline_seconds : Int32
      raw = ENV[DEADLINE_ENV]?

      if raw.nil? || raw.blank?
        raise Missing.new(DEADLINE_ENV) if LuckyEnv.production?
        return DEFAULT_DEADLINE_SECONDS
      end

      seconds = raw.to_i?

      unless seconds && seconds >= MIN_DEADLINE_SECONDS && seconds <= MAX_DEADLINE_SECONDS
        raise InvalidDeadline.new(raw)
      end

      seconds
    end
  end

  class CloudTasksDocsBuildQueue < DocsBuildQueue
    API_HOST = "https://cloudtasks.googleapis.com"

    # The deadline is not a constant here any more. It has to equal the
    # docs-launcher Cloud Run request timeout, terraform derives both from one
    # local, and this reads that. See CloudTasksConfig.deadline_seconds.

    # Test seam. Receives the queue path and the serialised task, and returns
    # nothing. Defaults to the real API call, so production works with nothing
    # installed; a spec swaps it out to assert on the task without a network.
    class_property transport : Proc(String, String, Nil) = ->(queue_path : String, task_json : String) {
      CloudTasksDocsBuildQueue.submit(queue_path, task_json)
    }

    # Builds the Cloud Tasks `CreateTask` body.
    #
    # Separated from sending it because the shape is the contract, and a
    # contract that can only be checked by dispatching a real task is a
    # contract nobody checks.
    def self.task_json(
      launcher_url : String,
      audience : String,
      invoker : String,
      task : DocsBuildTask,
      deadline_seconds : Int32 = CloudTasksConfig.deadline_seconds,
    ) : String
      {
        task: {
          # Per task, not a queue setting: Cloud Tasks has no queue level
          # dispatch deadline for an HTTP target. Left unset it defaults to
          # 600s, and the launcher holds the request open for the whole build,
          # so a slow shard would be killed mid compile and redelivered
          # forever.
          dispatchDeadline: "#{deadline_seconds}s",
          httpRequest:      {
            httpMethod: "POST",
            url:        "#{launcher_url.rstrip('/')}#{DocsBuildQueue::PATH}",
            headers:    {"Content-Type": "application/json"},
            body:       Base64.strict_encode(task.to_json),
            oidcToken:  {
              serviceAccountEmail: invoker,
              # The launcher verifies this audience. Anything else is a token
              # minted for a different service and must not be accepted.
              #
              # Separate from the URL, and it has to be: the launcher cannot be
              # told its own URL without terraform consuming its own output, so
              # when these were one value the check raised on every dispatch
              # and nothing was ever built. Declared as a custom audience on
              # the service, so Cloud Run accepts it too.
              audience: audience,
            },
          },
        },
      }.to_json
    end

    def enqueue(package_name : String, version : String) : String?
      task = DocsBuildTask.new(package_name, version, UUID.random.to_s)

      @@transport.call(
        CloudTasksConfig.queue_path,
        self.class.task_json(
          CloudTasksConfig.fetch(CloudTasksConfig::LAUNCHER_ENV),
          CloudTasksConfig.fetch(CloudTasksConfig::AUDIENCE_ENV),
          CloudTasksConfig.fetch(CloudTasksConfig::INVOKER_ENV),
          task
        )
      )

      task.build_id
    rescue ex : Exception
      # A queue that cannot be reached must not turn a docs page into a 500.
      # The row stays pending with no build id, which is visible in the data,
      # and the next reader after the retry floor tries again.
      Lucky::Log.dexter.warn do
        {docs_build_enqueue_failed: "#{package_name} #{version}", error: ex.message}
      end
      nil
    end

    protected def self.submit(queue_path : String, task_json : String) : Nil
      response = HTTP::Client.post(
        "#{API_HOST}/v2/#{queue_path}/tasks",
        headers: HTTP::Headers{
          "Authorization" => "Bearer #{GoogleMetadata.access_token}",
          "Content-Type"  => "application/json",
        },
        body: task_json
      )

      unless response.success?
        raise "Cloud Tasks refused the build request: #{response.status_code} #{response.body}"
      end
    end
  end

  # Development and test. No broker of any kind, and no Google.
  #
  # It records rather than builds, and that is the honest behaviour for this
  # app: crystaldocs has never built documentation in any environment, and a
  # local build would need the sandbox, the registry database and object
  # storage that only crystalshards has. A developer running `make dev` sees
  # the request logged and the row left pending, which is exactly what the
  # page renders.
  class InProcessDocsBuildQueue < DocsBuildQueue
    def enqueue(package_name : String, version : String) : String?
      build_id = UUID.random.to_s

      Lucky::Log.dexter.info do
        {docs_build_requested: "#{package_name} #{version}", build_id: build_id, transport: "in-process"}
      end

      build_id
    end
  end
end
