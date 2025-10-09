# Scheduled backup for CrystalGigs PostgreSQL
resource "kubectl_manifest" "crystalgigs_postgres_backup" {
  yaml_body = <<-YAML
    apiVersion: postgresql.cnpg.io/v1
    kind: ScheduledBackup
    metadata:
      name: crystalgigs-daily-backup
      namespace: ${kubernetes_namespace.crystalgigs.metadata[0].name}
    spec:
      schedule: "0 2 * * *" # 2 AM daily
      backupOwnerReference: self
      cluster:
        name: crystalgigs-postgres
      method: barmanObjectStore
      target: primary
  YAML

  depends_on = [kubectl_manifest.crystalgigs_postgres]
}
