require "json"
require "http/client"

module CrystalDocs
  # Service for managing documentation builds in Kubernetes
  class DocBuildService
    KUBERNETES_API_URL = ENV["KUBERNETES_SERVICE_HOST"]? ? "https://kubernetes.default.svc" : "http://localhost:8001"
    NAMESPACE = "crystaldocs"
    
    # Create a documentation build job
    def self.create_build_job(shard_name : String, shard_version : String, github_repo : String, content_path : String)
      job_name = "doc-build-#{shard_name.downcase.gsub(/[^a-z0-9]/, "-")}-#{Time.utc.to_unix}"
      
      job_manifest = generate_job_manifest(job_name, shard_name, shard_version, github_repo, content_path)
      
      begin
        response = kubernetes_api_request("POST", "/apis/batch/v1/namespaces/#{NAMESPACE}/jobs", job_manifest)
        
        if response.status_code == 201
          puts "Created documentation build job: #{job_name}"
          
          # Update database with building status
          update_documentation_status(content_path, "building", "Job #{job_name} created")
          
          job_name
        else
          error_msg = "Failed to create Kubernetes job: #{response.status_code} - #{response.body}"
          puts error_msg
          update_documentation_status(content_path, "failed", error_msg)
          nil
        end
      rescue ex : Exception
        error_msg = "Error creating build job: #{ex.message}"
        puts error_msg
        update_documentation_status(content_path, "failed", error_msg)
        nil
      end
    end
    
    # Check the status of a documentation build job
    def self.get_job_status(job_name : String)
      begin
        response = kubernetes_api_request("GET", "/apis/batch/v1/namespaces/#{NAMESPACE}/jobs/#{job_name}")
        
        if response.status_code == 200
          job = JSON.parse(response.body)
          status = job.dig("status").as_h
          
          if status["succeeded"]? && status["succeeded"].as_i > 0
            "succeeded"
          elsif status["failed"]? && status["failed"].as_i > 0
            "failed"
          elsif status["active"]? && status["active"].as_i > 0
            "running"
          else
            "pending"
          end
        else
          "unknown"
        end
      rescue ex : Exception
        puts "Error checking job status: #{ex.message}"
        "unknown"
      end
    end
    
    # List all documentation build jobs
    def self.list_build_jobs
      begin
        response = kubernetes_api_request("GET", "/apis/batch/v1/namespaces/#{NAMESPACE}/jobs?labelSelector=type=documentation-build")
        
        if response.status_code == 200
          jobs = JSON.parse(response.body)
          jobs.dig("items").as_a.map do |job|
            {
              name: job.dig("metadata", "name").as_s,
              status: extract_job_status(job),
              created: job.dig("metadata", "creationTimestamp").as_s,
              shard: job.dig("spec", "template", "spec", "containers", 0, "env").as_a.find { |env| env["name"].as_s == "SHARD_NAME" }.try &.["value"].as_s || "unknown"
            }
          end
        else
          [] of Hash(Symbol, String)
        end
      rescue ex : Exception
        puts "Error listing build jobs: #{ex.message}"
        [] of Hash(Symbol, String)
      end
    end
    
    # Clean up completed jobs older than specified hours
    def self.cleanup_old_jobs(hours_old = 24)
      cutoff_time = Time.utc - Time::Span.new(hours: hours_old)
      
      jobs = list_build_jobs
      jobs.each do |job|
        created_at = Time.parse_iso8601(job[:created])
        if created_at < cutoff_time && (job[:status] == "succeeded" || job[:status] == "failed")
          delete_job(job[:name])
        end
      end
    end
    
    private def self.generate_job_manifest(job_name : String, shard_name : String, shard_version : String, github_repo : String, content_path : String)
      {
        apiVersion: "batch/v1",
        kind: "Job",
        metadata: {
          name: job_name,
          namespace: NAMESPACE,
          labels: {
            app: "doc-builder",
            type: "documentation-build",
            shard: shard_name.downcase.gsub(/[^a-z0-9]/, "-")
          }
        },
        spec: {
          completions: 1,
          parallelism: 1,
          backoffLimit: 2,
          ttlSecondsAfterFinished: 3600,
          template: {
            metadata: {
              labels: {
                app: "doc-builder",
                type: "documentation-build"
              }
            },
            spec: {
              restartPolicy: "Never",
              securityContext: {
                runAsNonRoot: true,
                runAsUser: 1000,
                fsGroup: 1000
              },
              containers: [{
                name: "doc-builder",
                image: "crystallang/crystal:1.10.1-alpine",
                command: ["/bin/sh"],
                args: ["/scripts/build-docs.sh"],
                env: [
                  { name: "SHARD_NAME", value: shard_name },
                  { name: "SHARD_VERSION", value: shard_version },
                  { name: "GITHUB_REPO", value: github_repo },
                  { name: "CONTENT_PATH", value: content_path },
                  { name: "MINIO_ACCESS_KEY", valueFrom: { secretKeyRef: { name: "minio-credentials", key: "access-key" } } },
                  { name: "MINIO_SECRET_KEY", valueFrom: { secretKeyRef: { name: "minio-credentials", key: "secret-key" } } },
                  { name: "POSTGRES_PASSWORD", valueFrom: { secretKeyRef: { name: "postgresql-credentials", key: "password" } } }
                ],
                volumeMounts: [
                  { name: "build-scripts", mountPath: "/scripts", readOnly: true },
                  { name: "work-storage", mountPath: "/tmp" }
                ],
                resources: {
                  requests: { cpu: "100m", memory: "256Mi" },
                  limits: { cpu: "1000m", memory: "1Gi" }
                },
                securityContext: {
                  allowPrivilegeEscalation: false,
                  readOnlyRootFilesystem: false,
                  capabilities: { drop: ["ALL"] }
                }
              }],
              volumes: [
                {
                  name: "build-scripts",
                  configMap: { name: "doc-build-script", defaultMode: 493 } # 0755 in decimal
                },
                {
                  name: "work-storage",
                  emptyDir: { sizeLimit: "2Gi" }
                }
              ],
              nodeSelector: { "kubernetes.io/arch": "amd64" }
            }
          }
        }
      }.to_json
    end
    
    private def self.kubernetes_api_request(method : String, path : String, body : String? = nil)
      headers = HTTP::Headers{
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{service_account_token}"
      }
      
      client = HTTP::Client.new(URI.parse(KUBERNETES_API_URL))
      client.tls_insecure = true if KUBERNETES_API_URL.starts_with?("https")
      
      case method
      when "GET"
        client.get(path, headers: headers)
      when "POST"
        client.post(path, headers: headers, body: body)
      when "DELETE"
        client.delete(path, headers: headers)
      else
        raise "Unsupported HTTP method: #{method}"
      end
    end
    
    private def self.service_account_token
      if File.exists?("/var/run/secrets/kubernetes.io/serviceaccount/token")
        File.read("/var/run/secrets/kubernetes.io/serviceaccount/token").strip
      else
        ENV["KUBERNETES_TOKEN"]? || ""
      end
    end
    
    private def self.update_documentation_status(content_path : String, status : String, log : String)
      begin
        CrystalDocs::DB.exec(
          "UPDATE documentation SET build_status = $1, build_log = $2, updated_at = NOW() WHERE content_path = $3",
          status, log, content_path
        )
      rescue ex : Exception
        puts "Error updating documentation status: #{ex.message}"
      end
    end
    
    private def self.extract_job_status(job)
      status = job.dig("status").as_h
      
      if status["succeeded"]? && status["succeeded"].as_i > 0
        "succeeded"
      elsif status["failed"]? && status["failed"].as_i > 0
        "failed"
      elsif status["active"]? && status["active"].as_i > 0
        "running"
      else
        "pending"
      end
    end
    
    private def self.delete_job(job_name : String)
      begin
        response = kubernetes_api_request("DELETE", "/apis/batch/v1/namespaces/#{NAMESPACE}/jobs/#{job_name}")
        if response.status_code == 200
          puts "Deleted old job: #{job_name}"
        end
      rescue ex : Exception
        puts "Error deleting job #{job_name}: #{ex.message}"
      end
    end
  end
end