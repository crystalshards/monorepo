require "http/client"
require "json"
require "uuid"

module CrystalShards
  # Confines the compile to a one-shot Kubernetes Job in a namespace whose
  # NetworkPolicy allows nothing but object storage.
  #
  # Environment is per-container while the network namespace is per-pod, and
  # this design leans on exactly that. One Job runs three steps in order:
  #
  #   initContainer "fetch"    trusted, has storage credentials, pulls the
  #                            source tarball into a shared emptyDir
  #   initContainer "build"    UNTRUSTED, has no environment at all, runs
  #                            `crystal docs`; shard macros execute here
  #   container     "upload"   trusted, has storage credentials, pushes the
  #                            generated documentation back
  #
  # InitContainers run to completion in declared order before the main
  # container starts, so credentials exist only while trusted code is running.
  # The untrusted step can open a socket to object storage and nothing else,
  # and holds no credential to authenticate with, so that reachability buys an
  # attacker a connection that gets refused.
  #
  # The caller's interface is unchanged: source goes in as a directory and
  # documentation comes back as a directory. Staging through object storage is
  # what lets the build pod stay unable to talk to anything else.
  class KubernetesDocsSandbox < DocsSandbox
    SERVICE_HOST_ENV = "KUBERNETES_SERVICE_HOST"
    SERVICE_PORT_ENV = "KUBERNETES_SERVICE_PORT"
    TOKEN_PATH       = "/var/run/secrets/kubernetes.io/serviceaccount/token"
    CA_PATH          = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"

    # Where `mc` keeps the credentials it writes. Mounted by the trusted
    # steps only.
    MC_CONFIG_DIR = "/mc-config"

    @namespace : String
    @scratch_prefix : String
    @runtime_class : String?

    def initialize(@storage : ScratchStorage = StorageService.build_scratch)
      @namespace = ENV.fetch("DOCS_SANDBOX_NAMESPACE", "crystalshards-docs-sandbox")
      @scratch_prefix = ENV.fetch("DOCS_SANDBOX_SCRATCH_PREFIX", "build-scratch")
      @runtime_class = ENV["DOCS_SANDBOX_RUNTIME_CLASS"]?.presence
    end

    def description : String
      runtime = @runtime_class ? ", runtimeClass #{@runtime_class}" : ""
      "kubernetes Job in #{@namespace}, storage-only egress, no environment in the build step#{runtime}"
    end

    def build_docs(source_dir : String, output_dir : String) : Bool
      build_id = UUID.random.to_s
      source_key = "#{@scratch_prefix}/#{build_id}/source.tar.gz"
      docs_key = "#{@scratch_prefix}/#{build_id}/#{DOCS_JSON}"

      stage_source(source_dir, source_key)

      job_name = "docs-build-#{build_id[0, 8]}"
      create_job(job_name, source_key, docs_key)

      unless wait_for_job(job_name)
        log_error "Sandboxed build Job #{job_name} did not succeed"
        return false
      end

      collect_docs(docs_key, output_dir)

      # The compiler can exit 0 without writing anything useful, so the Job
      # succeeding is never the whole story: the artifact has to parse.
      unless DocsSandbox.valid_docs_json?(File.join(output_dir, DOCS_JSON))
        log_error "Sandboxed build produced no usable #{DOCS_JSON}"
        return false
      end

      true
    ensure
      cleanup(build_id.to_s) if build_id
    end

    private def stage_source(source_dir : String, key : String)
      tarball = File.tempname("docs_source", ".tar.gz")

      status = Process.run("tar", ["-czf", tarball, "-C", source_dir, "."])
      raise DocsSandbox::Unavailable.new("Could not archive source for the sandbox") unless status.success?

      @storage.upload_scratch(key, File.read(tarball))
    ensure
      File.delete(tarball) if tarball && File.exists?(tarball)
    end

    # The result comes back as one regular file, not an archive.
    #
    # It used to be a tarball, which was a hole: the directory it was built
    # from is written by the untrusted step, so a shard could plant a symlink
    # or a `../` member and have this trusted side extract it onto the worker.
    # A single JSON file has no members to traverse with, so the whole class
    # of attack disappears rather than being validated against.
    private def collect_docs(key : String, output_dir : String)
      Dir.mkdir_p(output_dir)
      File.write(File.join(output_dir, DOCS_JSON), @storage.download_scratch(key))
    end

    private def create_job(name : String, source_key : String, docs_key : String)
      response = api_request("POST", "/apis/batch/v1/namespaces/#{@namespace}/jobs",
        job_manifest(name, source_key, docs_key).to_json)

      unless response.success?
        raise DocsSandbox::Unavailable.new(
          "Could not create the sandbox Job: #{response.status_code} #{response.body}"
        )
      end
    end

    # Polls until the Job reports success or failure. The Job also carries its
    # own activeDeadlineSeconds, so the cluster stops a runaway build even if
    # this process dies.
    private def wait_for_job(name : String) : Bool
      deadline = Time.monotonic + DocsSandbox.timeout_seconds.seconds

      while Time.monotonic < deadline
        response = api_request("GET", "/apis/batch/v1/namespaces/#{@namespace}/jobs/#{name}")
        return false unless response.success?

        status = JSON.parse(response.body)["status"]?
        if status
          return true if status["succeeded"]?.try(&.as_i?).try(&.> 0)
          return false if status["failed"]?.try(&.as_i?).try(&.> 0)
        end

        sleep 2.seconds
      end

      log_error "Sandboxed build Job #{name} exceeded #{DocsSandbox.timeout_seconds}s"
      false
    end

    private def cleanup(build_id : String)
      api_request("DELETE",
        "/apis/batch/v1/namespaces/#{@namespace}/jobs/docs-build-#{build_id[0, 8]}?propagationPolicy=Background")
      @storage.delete_scratch_prefix("#{@scratch_prefix}/#{build_id}")
    rescue ex
      log_error "Could not clean up sandbox build #{build_id}: #{ex.message}"
    end

    private def job_manifest(name : String, source_key : String, docs_key : String)
      {
        apiVersion: "batch/v1",
        kind:       "Job",
        metadata:   {
          name:      name,
          namespace: @namespace,
          labels:    {app: "docs-sandbox"},
        },
        spec: {
          backoffLimit:            0,
          ttlSecondsAfterFinished: 300,
          activeDeadlineSeconds:   DocsSandbox.timeout_seconds,
          template:                {
            metadata: {labels: {app: "docs-sandbox"}},
            spec:     {
              restartPolicy:                "Never",
              runtimeClassName:             @runtime_class,
              automountServiceAccountToken: false,
              serviceAccountName:           "docs-sandbox",
              securityContext:              {
                runAsNonRoot:   true,
                runAsUser:      1000,
                fsGroup:        1000,
                seccompProfile: {type: "RuntimeDefault"},
              },
              volumes: [
                {name: "workspace", emptyDir: {sizeLimit: "2Gi"}},
                {name: "tmp", emptyDir: {medium: "Memory", sizeLimit: "256Mi"}},
                # Mounted only by the trusted steps, so the credentials `mc`
                # writes never sit on a volume the build can read. It lives
                # and dies with the Job.
                {name: "mc-config", emptyDir: {medium: "Memory", sizeLimit: "1Mi"}},
              ],
              initContainers: [
                storage_container("fetch", fetch_command(source_key)),
                # The untrusted step. No env block at all, so nothing from the
                # cluster or our configuration is readable from a shard macro.
                {
                  name:            "build",
                  image:           DocsSandbox.image,
                  command:         ["sh", "-c", build_command],
                  workingDir:      "/workspace",
                  securityContext: hardened_security_context,
                  resources:       resources,
                  volumeMounts:    volume_mounts,
                },
              ],
              containers: [storage_container("upload", upload_command(docs_key))],
            },
          },
        },
      }
    end

    # Trusted steps: they carry storage credentials but never execute shard
    # code, they only move an archive in or out.
    private def storage_container(name : String, command : String)
      {
        name:            name,
        image:           ENV.fetch("DOCS_SANDBOX_STORAGE_IMAGE", "minio/mc:latest"),
        command:         ["sh", "-c", command],
        securityContext: hardened_security_context,
        resources:       resources,
        # Trusted steps additionally mount the mc config volume. The build
        # step does not, which is the point: `mc alias set` writes the access
        # and secret key to disk, so that file must not live anywhere the
        # untrusted container can read.
        volumeMounts: volume_mounts + [{name: "mc-config", mountPath: MC_CONFIG_DIR}],
        env:          storage_env,
      }
    end

    private def fetch_command(source_key : String) : String
      "#{mc_alias} && #{mc} cp local/#{scratch_bucket}/#{source_key} /workspace/source.tar.gz && " \
      "mkdir -p /workspace/src && tar -xzf /workspace/source.tar.gz -C /workspace/src && " \
      "rm /workspace/source.tar.gz"
    end

    # `--format=json` sends the document to stdout rather than writing an
    # HTML tree, so the shell captures it. That one file is the whole
    # artifact: we render documentation ourselves and never store
    # shard-authored HTML.
    private def build_command : String
      "mkdir -p /workspace/docs && cd /workspace/src && " \
      "crystal docs --format=json > /workspace/docs/#{DOCS_JSON}"
    end

    # The path being uploaded was written by the untrusted step, so it is
    # checked before it is read. A symlink here would make the trusted
    # container copy whatever it points at, its own /proc included, straight
    # into object storage.
    private def upload_command(docs_key : String) : String
      artifact = "/workspace/docs/#{DOCS_JSON}"

      "test -f #{artifact} && test ! -L #{artifact} && " \
      "#{mc_alias} && #{mc} cp #{artifact} local/#{scratch_bucket}/#{docs_key}"
    end

    # `--config-dir` keeps the written credentials on the volume only the
    # trusted containers mount, rather than in HOME on a shared one.
    private def mc_alias : String
      "#{mc} alias set local \"$MINIO_ENDPOINT\" \"$MINIO_ACCESS_KEY\" \"$MINIO_SECRET_KEY\""
    end

    # Every `mc` call has to use the same config directory, or the copy will
    # not find the alias the first call wrote.
    private def mc : String
      "mc --config-dir #{MC_CONFIG_DIR}"
    end

    private def scratch_bucket : String
      ENV.fetch("MINIO_DOCS_BUCKET", "crystal-docs")
    end

    private def storage_env
      %w[MINIO_ENDPOINT MINIO_ACCESS_KEY MINIO_SECRET_KEY].map do |key|
        {
          name: key,
          # Secrets are namespace scoped, and this Job runs in the sandbox
          # namespace, so it cannot read the application's secret. Terraform
          # provisions a separate, storage-only credential there: the trusted
          # fetch and upload steps need object storage and nothing else, and
          # the app's secret also carries the database URL and key base, which
          # have no business anywhere near a build.
          valueFrom: {secretKeyRef: {name: sandbox_secret_name, key: key.downcase}},
        }
      end
    end

    # The storage-only credential Terraform creates in the sandbox namespace.
    private def sandbox_secret_name : String
      ENV.fetch("DOCS_SANDBOX_SECRET_NAME", "docs-sandbox-storage")
    end

    private def hardened_security_context
      {
        allowPrivilegeEscalation: false,
        readOnlyRootFilesystem:   true,
        runAsNonRoot:             true,
        runAsUser:                1000,
        capabilities:             {drop: ["ALL"]},
      }
    end

    private def resources
      {
        limits:   {cpu: DocsSandbox.cpus, memory: DocsSandbox.memory},
        requests: {cpu: "500m", memory: "512Mi"},
      }
    end

    private def volume_mounts
      [
        {name: "workspace", mountPath: "/workspace"},
        {name: "tmp", mountPath: "/tmp"},
      ]
    end

    private def api_request(method : String, path : String, body : String? = nil) : HTTP::Client::Response
      host = ENV[SERVICE_HOST_ENV]?
      port = ENV[SERVICE_PORT_ENV]?

      unless host && port
        raise DocsSandbox::Unavailable.new(
          "DOCS_SANDBOX=kubernetes but this process is not running in a cluster " \
          "(#{SERVICE_HOST_ENV} is unset)."
        )
      end

      context = OpenSSL::SSL::Context::Client.new
      if File.exists?(CA_PATH)
        context.ca_certificates = CA_PATH
      else
        context.verify_mode = OpenSSL::SSL::VerifyMode::NONE
      end

      client = HTTP::Client.new(host, port.to_i, tls: context)
      client.read_timeout = 30.seconds

      headers = HTTP::Headers{"Content-Type" => "application/json"}
      headers["Authorization"] = "Bearer #{File.read(TOKEN_PATH).strip}" if File.exists?(TOKEN_PATH)

      client.exec(method, path, headers: headers, body: body)
    ensure
      client.try(&.close)
    end
  end
end
