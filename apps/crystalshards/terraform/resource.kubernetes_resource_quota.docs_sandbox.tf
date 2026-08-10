# Resource quota for the docs-sandbox namespace.
#
# Bounds the total cpu, memory, and pod count across ALL build Jobs in the
# namespace, so a flood of builds (or a shard author gaming the queue) cannot
# starve the rest of the cluster. Defaults allow roughly 10 concurrent builds
# at the per-build limits (2 cpu / 2Gi each) with headroom for Job churn.
resource "kubernetes_resource_quota" "docs_sandbox" {
  metadata {
    name      = "docs-sandbox-quota"
    namespace = kubernetes_namespace.docs_sandbox.metadata[0].name
  }

  spec {
    hard = {
      "pods"             = var.docs_sandbox_quota_max_pods
      "requests.cpu"     = var.docs_sandbox_quota_requests_cpu
      "requests.memory"  = var.docs_sandbox_quota_requests_memory
      "limits.cpu"       = var.docs_sandbox_quota_limits_cpu
      "limits.memory"    = var.docs_sandbox_quota_limits_memory
      "count/jobs.batch" = var.docs_sandbox_quota_max_pods
    }
  }
}
