# LimitRange for the docs-sandbox namespace.
#
# A build Job that omits resource limits still gets them: the default limit is
# intentionally the same value the worker passes to its Jobs (docs_sandbox_cpus
# / docs_sandbox_memory), so "Job forgot limits" and "Job set limits" behave
# identically. The max keeps a single build container from claiming more than
# its share of the namespace quota.
resource "kubernetes_limit_range" "docs_sandbox" {
  metadata {
    name      = "docs-sandbox-limits"
    namespace = kubernetes_namespace.docs_sandbox.metadata[0].name
  }

  spec {
    limit {
      type = "Container"

      default = {
        cpu    = var.docs_sandbox_cpus
        memory = var.docs_sandbox_memory
      }

      default_request = {
        cpu    = var.docs_sandbox_default_request_cpu
        memory = var.docs_sandbox_default_request_memory
      }

      max = {
        cpu    = var.docs_sandbox_max_cpu
        memory = var.docs_sandbox_max_memory
      }
    }
  }
}
