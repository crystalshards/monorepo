# PostgreSQL cluster for crystalshards
resource "kubectl_manifest" "crystalshards_postgres" {
  yaml_body = <<-YAML
    apiVersion: postgresql.cnpg.io/v1
    kind: Cluster
    metadata:
      name: crystalshards-postgres
      namespace: ${kubernetes_namespace.crystalshards.metadata[0].name}
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
          database: crystalshards_production
          owner: crystalshards

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
          destinationPath: "gs://${var.postgres_backup_bucket}/crystalshards"
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
