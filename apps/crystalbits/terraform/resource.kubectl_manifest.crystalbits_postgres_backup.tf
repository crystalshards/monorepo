# Scheduled backup for CrystalBits PostgreSQL
resource "kubectl_manifest" "crystalbits_postgres_backup" {
  yaml_body = <<-YAML
    apiVersion: postgresql.cnpg.io/v1
    kind: ScheduledBackup
    metadata:
      name: crystalbits-daily-backup
      namespace: ${kubernetes_namespace.crystalbits.metadata[0].name}
    spec:
      schedule: "0 2 * * *" # 2 AM daily
      backupOwnerReference: self
      cluster:
        name: crystalbits-postgres
      method: barmanObjectStore
      target: primary
  YAML

  depends_on = [kubectl_manifest.crystalbits_postgres]
}
