# PostgreSQL cluster for crystaldocs
resource "kubectl_manifest" "crystaldocs_postgres" {
  yaml_body = <<-YAML
    apiVersion: postgresql.cnpg.io/v1
    kind: Cluster
    metadata:
      name: crystaldocs-postgres
      namespace: ${kubernetes_namespace.crystaldocs.metadata[0].name}
    spec:
      instances: 2
      primaryUpdateStrategy: unsupervised

      postgresql:
        parameters:
          shared_buffers: "256MB"
          max_connections: "100"
          work_mem: "8MB"

      bootstrap:
        initdb:
          database: crystaldocs_production
          owner: crystaldocs

      storage:
        size: 10Gi
        storageClass: standard-rwo

      resources:
        requests:
          memory: "512Mi"
          cpu: "250m"
        limits:
          memory: "2Gi"
          cpu: "1000m"

      monitoring:
        enablePodMonitor: true

      backup:
        barmanObjectStore:
          destinationPath: "gs://${var.postgres_backup_bucket}/crystaldocs"
          googleCredentials:
            gkeEnvironment: true
          wal:
            compression: gzip
            maxParallel: 2
          data:
            compression: gzip
            jobs: 2
        retentionPolicy: "30d"
  YAML
}
