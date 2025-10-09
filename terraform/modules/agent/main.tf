terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
}

# Create namespace for the agent
resource "kubernetes_namespace" "claude" {
  metadata {
    name = "claude"
    labels = {
      name = "claude"
      app  = "crystalshards-agent"
    }
  }
}

# Create service account for the agent
resource "kubernetes_service_account" "claude_agent" {
  metadata {
    name      = "claude-agent"
    namespace = kubernetes_namespace.claude.metadata[0].name
  }
}

# Create ClusterRole with necessary permissions
resource "kubernetes_cluster_role" "claude_agent_role" {
  metadata {
    name = "claude-agent-role"
  }

  # Namespace access
  rule {
    api_groups = [""]
    resources  = ["namespaces"]
    verbs      = ["get", "list", "watch"]
  }

  # Pod management and inspection
  rule {
    api_groups = [""]
    resources  = ["pods", "pods/log", "pods/status"]
    verbs      = ["get", "list", "watch"]
  }

  # Deployment inspection
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "deployments/status", "replicasets", "statefulsets"]
    verbs      = ["get", "list", "watch"]
  }

  # Service inspection
  rule {
    api_groups = [""]
    resources  = ["services", "endpoints", "configmaps"]
    verbs      = ["get", "list", "watch"]
  }

  # Secret inspection (read-only for troubleshooting)
  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get", "list"]
  }

  # Events for troubleshooting
  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["get", "list", "watch"]
  }

  # PVC and storage
  rule {
    api_groups = [""]
    resources  = ["persistentvolumeclaims", "persistentvolumes"]
    verbs      = ["get", "list", "watch"]
  }

  # Ingress and networking
  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses", "networkpolicies"]
    verbs      = ["get", "list", "watch"]
  }

  # Custom resources for operators - CloudNativePG
  rule {
    api_groups = ["postgresql.cnpg.io"]
    resources  = ["clusters", "backups", "scheduledbackups"]
    verbs      = ["get", "list", "watch"]
  }

  # Redis Operator
  rule {
    api_groups = ["redis.redis.opstreelabs.in"]
    resources  = ["redis", "redisclusters"]
    verbs      = ["get", "list", "watch"]
  }

  # MinIO Operator
  rule {
    api_groups = ["minio.min.io"]
    resources  = ["tenants"]
    verbs      = ["get", "list", "watch"]
  }

  # Gateway API resources
  rule {
    api_groups = ["gateway.networking.k8s.io"]
    resources  = ["gateways", "httproutes", "gatewayclasses"]
    verbs      = ["get", "list", "watch"]
  }

  # Cert-manager resources
  rule {
    api_groups = ["cert-manager.io"]
    resources  = ["certificates", "certificaterequests", "issuers", "clusterissuers"]
    verbs      = ["get", "list", "watch"]
  }

  # Monitoring resources
  rule {
    api_groups = ["monitoring.coreos.com"]
    resources  = ["servicemonitors", "prometheusrules", "podmonitors"]
    verbs      = ["get", "list", "watch"]
  }

  # Nodes (for cluster health)
  rule {
    api_groups = [""]
    resources  = ["nodes"]
    verbs      = ["get", "list", "watch"]
  }

  # RBAC inspection
  rule {
    api_groups = ["rbac.authorization.k8s.io"]
    resources  = ["roles", "rolebindings", "clusterroles", "clusterrolebindings"]
    verbs      = ["get", "list", "watch"]
  }
}

# Bind ClusterRole to the service account
resource "kubernetes_cluster_role_binding" "claude_agent_binding" {
  metadata {
    name = "claude-agent-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.claude_agent_role.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.claude_agent.metadata[0].name
    namespace = kubernetes_namespace.claude.metadata[0].name
  }

  # Also bind the default service account for backward compatibility
  subject {
    kind      = "ServiceAccount"
    name      = "default"
    namespace = kubernetes_namespace.claude.metadata[0].name
  }
}
