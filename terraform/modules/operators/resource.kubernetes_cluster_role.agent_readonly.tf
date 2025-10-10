# Agent Read-Only ClusterRole
# Provides read-only access to cluster resources for debugging purposes
resource "kubernetes_cluster_role" "agent_readonly" {
  metadata {
    name = "crystalshards-agent-readonly"
    labels = {
      "app.kubernetes.io/name"       = "crystalshards-agent"
      "app.kubernetes.io/component"  = "rbac"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  # Core resources - Pods
  rule {
    api_groups = [""]
    resources  = ["pods", "pods/log", "pods/status"]
    verbs      = ["get", "list", "watch"]
  }

  # Core resources - Services
  rule {
    api_groups = [""]
    resources  = ["services", "endpoints"]
    verbs      = ["get", "list", "watch"]
  }

  # Core resources - ConfigMaps and Secrets (for debugging config issues)
  rule {
    api_groups = [""]
    resources  = ["configmaps", "secrets"]
    verbs      = ["get", "list"]
  }

  # Core resources - Events (for debugging)
  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["get", "list", "watch"]
  }

  # Core resources - Namespaces
  rule {
    api_groups = [""]
    resources  = ["namespaces"]
    verbs      = ["get", "list", "watch"]
  }

  # Core resources - PersistentVolumeClaims and PersistentVolumes
  rule {
    api_groups = [""]
    resources  = ["persistentvolumeclaims", "persistentvolumes"]
    verbs      = ["get", "list", "watch"]
  }

  # Apps resources - Deployments, StatefulSets, DaemonSets, ReplicaSets
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "statefulsets", "daemonsets", "replicasets"]
    verbs      = ["get", "list", "watch"]
  }

  # Batch resources - Jobs and CronJobs
  rule {
    api_groups = ["batch"]
    resources  = ["jobs", "cronjobs"]
    verbs      = ["get", "list", "watch"]
  }

  # Networking resources
  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["networkpolicies", "ingresses"]
    verbs      = ["get", "list", "watch"]
  }

  # CNPG PostgreSQL resources
  rule {
    api_groups = ["postgresql.cnpg.io"]
    resources  = ["clusters", "backups", "scheduledbackups", "poolers"]
    verbs      = ["get", "list", "watch"]
  }

  # Redis Operator resources
  rule {
    api_groups = ["redis.redis.opstreelabs.in"]
    resources  = ["redis", "redisclusters", "redissentinels", "redisreplications"]
    verbs      = ["get", "list", "watch"]
  }

  # MinIO Operator resources
  rule {
    api_groups = ["minio.min.io"]
    resources  = ["tenants"]
    verbs      = ["get", "list", "watch"]
  }

  # Cert-Manager resources
  rule {
    api_groups = ["cert-manager.io"]
    resources  = ["certificates", "certificaterequests", "issuers", "clusterissuers"]
    verbs      = ["get", "list", "watch"]
  }

  # Monitoring resources - ServiceMonitors and PrometheusRules
  rule {
    api_groups = ["monitoring.coreos.com"]
    resources  = ["servicemonitors", "prometheusrules", "prometheuses", "alertmanagers"]
    verbs      = ["get", "list", "watch"]
  }

  # KEDA autoscaling resources
  rule {
    api_groups = ["keda.sh"]
    resources  = ["scaledobjects", "scaledjobs", "triggerauthentications"]
    verbs      = ["get", "list", "watch"]
  }

  # Autoscaling resources
  rule {
    api_groups = ["autoscaling"]
    resources  = ["horizontalpodautoscalers"]
    verbs      = ["get", "list", "watch"]
  }

  # Storage resources
  rule {
    api_groups = ["storage.k8s.io"]
    resources  = ["storageclasses"]
    verbs      = ["get", "list", "watch"]
  }

  # RBAC resources (read-only for debugging)
  rule {
    api_groups = ["rbac.authorization.k8s.io"]
    resources  = ["roles", "rolebindings", "clusterroles", "clusterrolebindings"]
    verbs      = ["get", "list", "watch"]
  }

  # Node information (for debugging cluster issues)
  rule {
    api_groups = [""]
    resources  = ["nodes"]
    verbs      = ["get", "list", "watch"]
  }
}
