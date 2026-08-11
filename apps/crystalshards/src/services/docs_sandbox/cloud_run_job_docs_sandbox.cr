require "http/client"
require "json"
require "uuid"
require "../google_metadata"

module CrystalShards
  # Confines the compile to a one-shot Cloud Run Job execution that holds no
  # credentials at all.
  #
  # THIS IS THE PROPERTY THAT CHOSE CLOUD RUN OVER KUBERNETES, and it is the
  # one to protect if this file is ever edited. The `docs-build` service
  # account has ZERO IAM bindings. Not "read-only on one bucket", none. It
  # cannot call a Google API, it cannot read a secret, it cannot reach the
  # database, and an access token minted for it opens nothing. Everything it
  # needs arrives as two signed URLs minted here by the launcher, each good for
  # one object and one method and expiring in minutes:
  #
  #   DOCS_SOURCE_URL   signed GET   the prepared source tree, going in
  #   DOCS_UPLOAD_URL   signed PUT   the one artifact, coming out
  #
  # A shard macro that shells out during `crystal docs` therefore finds nothing
  # worth stealing: no key file, no metadata credential worth having, no
  # network path to anything but two opaque URLs that expire. Do not hand this
  # identity a bucket role because it would be convenient. The convenience is
  # the whole attack.
  #
  # The Kubernetes version of this file hand-built its confinement: a dedicated
  # namespace, a NetworkPolicy, a separate storage-only secret, non-root, and
  # dropped capabilities, all of which had to be correct simultaneously and
  # none of which the platform checked. Cloud Run gives per-execution isolation
  # as a platform default, so that scaffolding is gone rather than ported. What
  # is still ours to enforce, and is enforced below, is that the output is
  # validated before it is published, that the untrusted step never holds a
  # durable credential, and that nothing the build writes can decide where it
  # lands.
  class CloudRunJobDocsSandbox < DocsSandbox
    PROJECT_ENV = "GOOGLE_CLOUD_PROJECT"
    JOB_ENV     = "DOCS_BUILD_JOB"
    REGION_ENV  = "DOCS_BUILD_JOB_REGION"

    # Per-build scratch. Objects here are deleted in an `ensure`, and the
    # bucket carries a lifecycle rule on this prefix because a crashed
    # execution cannot run our ensure block.
    SCRATCH_PREFIX = "build-scratch"

    # The artifact is a single JSON document, so the PUT is signed for this
    # content type and the Job must send exactly it. GCS signs the content
    # type, so a mismatch is a 403 that would otherwise look like a failed
    # build.
    ARTIFACT_CONTENT_TYPE = "application/json"

    class Missing < Exception
      def initialize(key : String)
        super(<<-MESSAGE)
        #{key} is not set.

        Documentation is built in a Cloud Run Job, and the launcher will not
        start one without knowing which. Production requires all of:

          #{PROJECT_ENV}, #{JOB_ENV}, #{REGION_ENV}
        MESSAGE
      end
    end

    # Test seam. Receives the fully composed execution request and returns the
    # operation name; defaults to the real API call. A spec can assert on what
    # would be launched without a Google project.
    class_property runner : Proc(String, String, String)? = nil

    def initialize(@storage : ScratchStorage = StorageService.build_scratch)
    end

    def description : String
      "cloud run job #{env(JOB_ENV)} in #{env(REGION_ENV)}, no credentials in the build step, signed url in and out"
    end

    def build_docs(source_dir : String, output_dir : String) : Bool
      build_id = UUID.random.to_s
      source_key = "#{SCRATCH_PREFIX}/#{build_id}/source.tar.gz"
      docs_key = "#{SCRATCH_PREFIX}/#{build_id}/#{DOCS_JSON}"

      stage_source(source_dir, source_key)

      log_info "Building documentation under #{description}"

      unless run_execution(build_id, source_key, docs_key)
        log_error "Sandboxed build #{build_id} did not succeed"
        return false
      end

      collect_docs(docs_key, output_dir)

      # The compiler can exit 0 having written nothing useful, and this
      # artifact was produced by untrusted code, so the execution succeeding is
      # never the whole story. Nothing is published until it parses.
      unless DocsSandbox.valid_docs_json?(File.join(output_dir, DOCS_JSON))
        log_error "Sandboxed build produced no usable #{DOCS_JSON}"
        return false
      end

      true
    ensure
      cleanup(build_id.to_s) if build_id
    end

    # The Job receives the tree AFTER `shards install`, not the published
    # package tarball. It has no network beyond its two signed URLs, so it
    # cannot fetch dependencies itself, and `crystal docs` on a shard with
    # dependencies and no lib/ directory fails.
    private def stage_source(source_dir : String, key : String)
      tarball = File.tempname("docs_source", ".tar.gz")

      status = Process.run("tar", ["-czf", tarball, "-C", source_dir, "."])
      raise DocsSandbox::Unavailable.new("Could not archive source for the sandbox") unless status.success?

      @storage.upload_scratch(key, File.read(tarball))
    ensure
      File.delete(tarball) if tarball && File.exists?(tarball)
    end

    # The result comes back as one regular file, written to a path composed
    # here.
    #
    # It is not an archive, and that is load bearing rather than incidental.
    # The bytes were produced by the untrusted step, so if this were a tarball
    # the trusted side would be extracting attacker-controlled members and a
    # `../` entry or a symlink would write onto the launcher. A single JSON
    # document has no members to traverse with, so the whole class of attack
    # does not exist rather than being validated against. The build also cannot
    # choose where its output lands: the object key is baked into the signature
    # the launcher minted, and the local path is composed from output_dir here.
    private def collect_docs(key : String, output_dir : String)
      Dir.mkdir_p(output_dir)
      File.write(File.join(output_dir, DOCS_JSON), @storage.download_scratch(key))
    end

    # Starts one execution and waits for it.
    #
    # Waiting rather than returning is deliberate: the build identity cannot
    # write to the database, so the only process that can record whether this
    # build succeeded is this one. The Cloud Tasks request that triggered it
    # stays open for the duration, which is what its dispatch deadline is for.
    private def run_execution(build_id : String, source_key : String, docs_key : String) : Bool
      body = execution_request(source_key, docs_key)

      operation =
        if custom = @@runner
          custom.call(build_id, body)
        else
          start(body)
        end

      wait_for(operation)
    end

    # The execution overrides. Everything the build gets, it gets here.
    def execution_request(source_key : String, docs_key : String) : String
      {
        overrides: {
          taskCount:          1,
          timeout:            "#{DocsSandbox.timeout_seconds}s",
          containerOverrides: [
            {
              env: [
                {name: "DOCS_SOURCE_URL", value: @storage.scratch_signed_url(source_key, "GET")},
                {name: "DOCS_UPLOAD_URL", value: @storage.scratch_signed_url(docs_key, "PUT", ARTIFACT_CONTENT_TYPE)},
                # Passed rather than hardcoded in the image, so the header the
                # Job sends always matches the content type the URL was signed
                # for. Hardcoding it in two places is how that drifts into a
                # 403 that reads like a broken build.
                {name: "DOCS_UPLOAD_CONTENT_TYPE", value: ARTIFACT_CONTENT_TYPE},
              ],
            },
          ],
        },
      }.to_json
    end

    private def start(body : String) : String
      response = HTTP::Client.post(
        "#{api_host}/v2/projects/#{env(PROJECT_ENV)}/locations/#{env(REGION_ENV)}/jobs/#{env(JOB_ENV)}:run",
        headers: auth_headers,
        body: body
      )

      unless response.success?
        raise DocsSandbox::Unavailable.new(
          "Could not start the docs build job: #{response.status_code} #{response.body}"
        )
      end

      JSON.parse(response.body)["name"].as_s
    end

    # Polls the long-running operation the run request returned. The execution
    # also carries its own timeout, so a runaway build is stopped by Cloud Run
    # even if this process dies.
    private def wait_for(operation : String) : Bool
      deadline = Time.monotonic + DocsSandbox.timeout_seconds.seconds

      while Time.monotonic < deadline
        response = HTTP::Client.get("#{api_host}/v2/#{operation}", headers: auth_headers)
        return false unless response.success?

        parsed = JSON.parse(response.body)

        if parsed["done"]?.try(&.as_bool?)
          if error = parsed["error"]?
            log_error "Docs build execution failed: #{error}"
            return false
          end

          return true
        end

        sleep 2.seconds
      end

      log_error "Docs build execution exceeded #{DocsSandbox.timeout_seconds}s"
      false
    end

    private def cleanup(build_id : String)
      @storage.delete_scratch_prefix("#{SCRATCH_PREFIX}/#{build_id}")
    rescue ex
      log_error "Could not clean up sandbox build #{build_id}: #{ex.message}"
    end

    private def auth_headers : HTTP::Headers
      HTTP::Headers{
        "Authorization" => "Bearer #{GoogleMetadata.access_token}",
        "Content-Type"  => "application/json",
      }
    end

    # Regional endpoint. Cloud Run v2 serves regional resources from the
    # region's own host, and using the global one for a regional job is a
    # 404 that reads like a missing job.
    private def api_host : String
      "https://#{env(REGION_ENV)}-run.googleapis.com"
    end

    private def env(key : String) : String
      value = ENV[key]?
      raise Missing.new(key) if value.nil? || value.blank?
      value
    end
  end
end
