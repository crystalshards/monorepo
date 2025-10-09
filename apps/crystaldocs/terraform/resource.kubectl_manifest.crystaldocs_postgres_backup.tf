# Scheduled backup for CrystalDocs PostgreSQL
resource "kubectl_manifest" "crystaldocs_postgres_backup" {
  yaml_body = <<-YAML
    apiVersion: postgresql.cnpg.io/v1
    kind: ScheduledBackup
    metadata:
      name: crystaldocs-daily-backup
      namespace: ${kubernetes_namespace.crystaldocs.metadata[0].name}
    spec:
      schedule: "0 2 * * *" # 2 AM daily
      backupOwnerReference: self
      cluster:
        name: crystaldocs-postgres
      method: barmanObjectStore
      target: primary
  YAML

  depends_on = [kubectl_manifest.crystaldocs_postgres]
}
