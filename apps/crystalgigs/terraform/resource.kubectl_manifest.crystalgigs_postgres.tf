# PostgreSQL cluster for crystalgigs
resource "kubectl_manifest" "crystalgigs_postgres" {
  yaml_body = <<-YAML
    apiVersion: postgresql.cnpg.io/v1
    kind: Cluster
    metadata:
      name: crystalgigs-postgres
      namespace: ${kubernetes_namespace.crystalgigs.metadata[0].name}
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
          database: crystalgigs_production
          owner: crystalgigs

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
  YAML
}
