# Application secrets for crystalshards
resource "kubernetes_secret" "crystalshards_secrets" {
  metadata {
    name      = "crystalshards-secrets"
    namespace = kubernetes_namespace.crystalshards.metadata[0].name
  }

  data = {
    # CNPG creates a read-write service: <cluster-name>-rw
    # CNPG creates an app secret: <cluster-name>-app with username/password
    # Format: postgresql://app:password@service:5432/database
    database_url = "postgresql://app:PLACEHOLDER@crystalshards-postgres-rw:5432/crystalshards_production"

    # Redis URL for JoobQ workers - shared Redis in infrastructure namespace
    redis_url = "redis://shared-redis.infrastructure.svc.cluster.local:6379/0"

    # TODO: Generate proper SECRET_KEY_BASE with: openssl rand -hex 64
    # This is a placeholder - should use External Secrets Operator in production
    secret_key_base = "CHANGE_ME_IN_PRODUCTION_USE_EXTERNAL_SECRETS_OPERATOR"
  }

  type = "Opaque"
}
