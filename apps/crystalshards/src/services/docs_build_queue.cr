require "base64"
require "http/client"
require "json"
require "uuid"
require "./google_metadata"

module CrystalShards
  # Producer side of the documentation build queue, as used by the indexer.
  #
  # crystaldocs has the same producer, because both apps commission builds: a
  # reader opening a cold docs page, and this app indexing a new version. They
  # deliberately go to the same Cloud Tasks queue and the same launcher route,
  # so there is one way a build starts and one place it can be observed.
  #
  # This app must not start the `docs-build` Job directly even though it owns
  # the build pipeline. Starting one means minting signed object-storage URLs,
  # and only the `docs-launcher` identity holds that authority. Going through
  # the queue also makes the request durable: Cloud Run reclaims CPU once a
  # response is written, so work handed off during a webhook would otherwise be
  # cancelled before it began.
  abstract class DocsBuildQueue
    # The launcher route. crystaldocs targets the identical path; renaming it
    # on one side alone makes every dispatch a 404 and stops builds silently.
    PATH = "/internal/docs/build"

    class_property override : DocsBuildQueue? = nil

    def self.build : DocsBuildQueue
      if installed = @@override
        return installed
      end

      LuckyEnv.production? ? CloudTasksDocsBuildQueue.new : InProcessDocsBuildQueue.new
    end

    # Returns the build id, or nil when the request was never delivered.
    abstract def enqueue(shard_name : String, version : String) : String?
  end

  struct DocsBuildTask
    include JSON::Serializable

    # Named package_name on the wire because that is what the launcher parses
    # and what crystaldocs sends. This app calls the same value a shard name.
    getter package_name : String
    getter version : String
    getter build_id : String

    def initialize(@package_name : String, @version : String, @build_id : String)
    end
  end

  module CloudTasksConfig
    PROJECT_ENV  = "GOOGLE_CLOUD_PROJECT"
    QUEUE_ENV    = "DOCS_BUILD_QUEUE"
    LOCATION_ENV = "DOCS_BUILD_QUEUE_LOCATION"
    LAUNCHER_ENV = "DOCS_LAUNCHER_URL"
    INVOKER_ENV  = "DOCS_TASKS_SERVICE_ACCOUNT"
    DEADLINE_ENV = "DOCS_BUILD_DEADLINE_SECONDS"

    # Only used outside production. In production the deadline is required,
    # because it has to equal the docs-launcher Cloud Run request timeout and
    # terraform derives both from one value. Defaulting here would recreate
    # the second source of truth this variable exists to remove.
    DEFAULT_DEADLINE_SECONDS = 1800

    class Missing < Exception
      def initialize(key : String)
        super(<<-MESSAGE)
        #{key} is not set.

        Documentation builds are commissioned through Cloud Tasks. Production
        requires all of:

          #{PROJECT_ENV}, #{QUEUE_ENV}, #{LOCATION_ENV}, #{LAUNCHER_ENV}, #{INVOKER_ENV}, #{DEADLINE_ENV}

        In development and test the queue is in-process and none are read.
        MESSAGE
      end
    end

    def self.fetch(key : String) : String
      value = ENV[key]?
      raise Missing.new(key) if value.nil? || value.blank?
      value
    end

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
    # Must equal the docs-launcher Cloud Run request timeout, because the
    # launcher holds the request open for the whole build: it is the only
    # party in the chain that can write the outcome to the database. These
    # were two numbers in two places with nothing able to fail when they
    # drifted, and a wrong value passes every gate in the pipeline because
    # /api/health answers in milliseconds. It surfaces only as builds dying
    # mid-compile and being redelivered forever behind a green deploy.
    #
    # Terraform now derives the service timeout and this variable from one
    # local, and this reads that variable rather than carrying a copy. Cloud
    # Run env values are strings, hence the parse.
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

    # Test seam: queue path and serialised task in, nothing out.
    class_property transport : Proc(String, String, Nil) = ->(queue_path : String, task_json : String) {
      CloudTasksDocsBuildQueue.submit(queue_path, task_json)
    }

    # Built separately from being sent, because the shape is the contract with
    # a separate deployment and a contract that can only be checked by
    # dispatching a real task is a contract nobody checks.
    def self.task_json(launcher_url : String, invoker : String, task : DocsBuildTask, deadline_seconds : Int32 = CloudTasksConfig.deadline_seconds) : String
      {
        task: {
          # Per task, not a queue setting: Cloud Tasks has no queue level
          # dispatch deadline for an HTTP target, and unset means 600s.
          dispatchDeadline: "#{deadline_seconds}s",
          httpRequest:      {
            httpMethod: "POST",
            url:        "#{launcher_url.rstrip('/')}#{DocsBuildQueue::PATH}",
            headers:    {"Content-Type": "application/json"},
            body:       Base64.strict_encode(task.to_json),
            oidcToken:  {
              serviceAccountEmail: invoker,
              audience:            launcher_url,
            },
          },
        },
      }.to_json
    end

    def enqueue(shard_name : String, version : String) : String?
      task = DocsBuildTask.new(shard_name, version, UUID.random.to_s)

      @@transport.call(
        CloudTasksConfig.queue_path,
        self.class.task_json(
          CloudTasksConfig.fetch(CloudTasksConfig::LAUNCHER_ENV),
          CloudTasksConfig.fetch(CloudTasksConfig::INVOKER_ENV),
          task
        )
      )

      task.build_id
    rescue ex : Exception
      # Indexing a version is worth keeping even when the docs build could not
      # be commissioned. crystaldocs will ask for the build itself the first
      # time a reader opens the page.
      Log.warn(exception: ex) { "Could not enqueue a docs build for #{shard_name}@#{version}" }
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

  # Development and test. No broker, no Google project.
  #
  # It records rather than builds. Building locally needs a sandbox, and
  # DocsSandbox already refuses to run one unconfined unless a developer asks
  # for it by name, so quietly starting one here would route around that.
  class InProcessDocsBuildQueue < DocsBuildQueue
    def enqueue(shard_name : String, version : String) : String?
      build_id = UUID.random.to_s

      Log.info { "Docs build requested for #{shard_name}@#{version} (#{build_id}, in-process)" }

      build_id
    end
  end
end
