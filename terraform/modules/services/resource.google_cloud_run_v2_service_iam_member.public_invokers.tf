# allUsers may invoke the four public services.
#
# This is not what makes them public. Ingress is
# INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER, so the only thing that can deliver a
# request is the load balancer in the edge module, and the run.app URL answers
# nobody. What this binding does is stop the load balancer's requests from being
# rejected at the IAM layer, since a serverless NEG forwards the end user's
# request without an identity attached.
#
# docs-launcher is deliberately not in this loop.
resource "google_cloud_run_v2_service_iam_member" "public_invokers" {
  for_each = local.apps

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.apps[each.key].name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
