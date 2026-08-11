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

    class Missing < Exception
      def initialize(key : String)
        super(<<-MESSAGE)
        #{key} is not set.

        Documentation builds are commissioned through Cloud Tasks, and this
        app will not enqueue one without knowing where to send it. Production
        requires all of:

          #{PROJECT_ENV}, #{QUEUE_ENV}, #{LOCATION_ENV}, #{LAUNCHER_ENV}, #{INVOKER_ENV}

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
  end

  class CloudTasksDocsBuildQueue < DocsBuildQueue
    API_HOST = "https://cloudtasks.googleapis.com"

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
    #
    # The body is base64 because Cloud Tasks carries an HTTP body as bytes.
    # The OIDC block is not optional: docs-launcher grants run.invoker to one
    # service account and nothing else, so a task without a token is a 403 on
    # every dispatch.
    def self.task_json(launcher_url : String, invoker : String, task : DocsBuildTask) : String
      {
        task: {
          httpRequest: {
            httpMethod: "POST",
            url:        "#{launcher_url.rstrip('/')}#{DocsBuildQueue::PATH}",
            headers:    {"Content-Type": "application/json"},
            body:       Base64.strict_encode(task.to_json),
            oidcToken:  {
              serviceAccountEmail: invoker,
              # The launcher verifies this audience. Anything else is a token
              # minted for a different service and must not be accepted.
              audience: launcher_url,
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

  # Development and test. No Redis, no Google, no broker of any kind.
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
