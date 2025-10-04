# Application secrets for crystalgigs
resource "kubernetes_secret" "crystalgigs_secrets" {
  metadata {
    name      = "crystalgigs-secrets"
    namespace = kubernetes_namespace.crystalgigs.metadata[0].name
  }

  data = {
    # CNPG creates a read-write service: <cluster-name>-rw
    # CNPG creates an app secret: <cluster-name>-app with username/password
    # Format: postgresql://app:password@service:5432/database
    database_url = "postgresql://app:PLACEHOLDER@crystalgigs-postgres-rw:5432/crystalgigs_production"

    # TODO: Generate proper SECRET_KEY_BASE with: openssl rand -hex 64
    # This is a placeholder - should use External Secrets Operator in production
    secret_key_base = "CHANGE_ME_IN_PRODUCTION_USE_EXTERNAL_SECRETS_OPERATOR"
  }

  type = "Opaque"
}
