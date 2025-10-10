# Agent Read-Only ClusterRoleBinding
# Binds the read-only ClusterRole to the agent service account
resource "kubernetes_cluster_role_binding" "agent_readonly" {
  metadata {
    name = "crystalshards-agent-readonly"
    labels = {
      "app.kubernetes.io/name"       = "crystalshards-agent"
      "app.kubernetes.io/component"  = "rbac"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.agent_readonly.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.agent_sa.metadata[0].name
    namespace = kubernetes_service_account.agent_sa.metadata[0].namespace
  }
}
