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

    class Missing < Exception
      def initialize(key : String)
        super(<<-MESSAGE)
        #{key} is not set.

        Documentation builds are commissioned through Cloud Tasks. Production
        requires all of:

          #{PROJECT_ENV}, #{QUEUE_ENV}, #{LOCATION_ENV}, #{LAUNCHER_ENV}, #{INVOKER_ENV}

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
  end

  class CloudTasksDocsBuildQueue < DocsBuildQueue
    API_HOST = "https://cloudtasks.googleapis.com"

    # Must match the docs-launcher Cloud Run request timeout. Cloud Tasks has
    # no queue level dispatch deadline for an HTTP target, so leaving it unset
    # defaults to 600s and kills long builds mid compile, forever.
    DISPATCH_DEADLINE_SECONDS = 1800

    # Test seam: queue path and serialised task in, nothing out.
    class_property transport : Proc(String, String, Nil) = ->(queue_path : String, task_json : String) {
      CloudTasksDocsBuildQueue.submit(queue_path, task_json)
    }

    # Built separately from being sent, because the shape is the contract with
    # a separate deployment and a contract that can only be checked by
    # dispatching a real task is a contract nobody checks.
    def self.task_json(launcher_url : String, invoker : String, task : DocsBuildTask) : String
      {
        task: {
          dispatchDeadline: "#{DISPATCH_DEADLINE_SECONDS}s",
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
