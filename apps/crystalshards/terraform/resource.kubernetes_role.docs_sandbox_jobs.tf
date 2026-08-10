# RBAC letting the crystalshards worker create and reap docs build Jobs.
#
# This is a Role scoped to the docs-sandbox namespace only, never a ClusterRole:
# the worker must be able to manage build Jobs here and nowhere else.
resource "kubernetes_role" "docs_sandbox_jobs" {
  metadata {
    name      = "docs-sandbox-jobs"
    namespace = kubernetes_namespace.docs_sandbox.metadata[0].name
  }

  # Create build Jobs, track them to completion, and delete them when reaped.
  rule {
    api_groups = ["batch"]
    resources  = ["jobs"]
    verbs      = ["create", "get", "list", "watch", "delete"]
  }

  # Inspect build pods (status, failure diagnostics).
  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list"]
  }

  # Read build logs for failure reporting.
  rule {
    api_groups = [""]
    resources  = ["pods/log"]
    verbs      = ["get", "list"]
  }
}

# The worker deployment does not set service_account_name, so its pods run as
# the crystalshards namespace's "default" ServiceAccount and that is what this
# binding targets. RECOMMENDED follow-up: give the worker a dedicated
# ServiceAccount and re-point this binding at it, so the default SA carries no
# permissions anywhere.
resource "kubernetes_role_binding" "docs_sandbox_jobs" {
  metadata {
    name      = "docs-sandbox-jobs"
    namespace = kubernetes_namespace.docs_sandbox.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.docs_sandbox_jobs.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "default"
    namespace = kubernetes_namespace.crystalshards.metadata[0].name
  }
}
