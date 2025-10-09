# Scheduled backup for CrystalShards PostgreSQL
resource "kubectl_manifest" "crystalshards_postgres_backup" {
  yaml_body = <<-YAML
    apiVersion: postgresql.cnpg.io/v1
    kind: ScheduledBackup
    metadata:
      name: crystalshards-daily-backup
      namespace: ${kubernetes_namespace.crystalshards.metadata[0].name}
    spec:
      schedule: "0 2 * * *" # 2 AM daily
      backupOwnerReference: self
      cluster:
        name: crystalshards-postgres
      method: barmanObjectStore
      target: primary
  YAML

  depends_on = [kubectl_manifest.crystalshards_postgres]
}
