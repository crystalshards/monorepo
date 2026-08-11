# The OIDC identity Cloud Tasks presents when it calls docs-launcher.
#
# docs-launcher has ingress ALL, because Cloud Tasks reaches it over its public
# run.app URL and is neither internal traffic nor load balancer traffic. IAM is
# what makes it private instead: this is the only principal holding
# roles/run.invoker on it, and an unauthenticated call is a 403.
#
# It holds nothing else. It exists to be a token subject, not to do work.
resource "google_service_account" "docs_tasks" {
  project      = var.project_id
  account_id   = "docs-tasks"
  display_name = "Cloud Tasks OIDC identity for documentation build dispatch"
}
