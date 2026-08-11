# One backend service per app, each fronting that app's serverless NEG.
#
# No health check is attached: serverless NEG backends do not take one, because
# Cloud Run reports its own readiness and the load balancer has nothing to probe.
resource "google_compute_backend_service" "app" {
  for_each = google_compute_region_network_endpoint_group.app

  project = var.project_id
  name    = "${var.name_prefix}-${each.key}"

  # EXTERNAL_MANAGED is the global external Application Load Balancer. The
  # forwarding rules below must use the same scheme, the two cannot be mixed.
  load_balancing_scheme = "EXTERNAL_MANAGED"
  protocol              = "HTTP"

  backend {
    group = each.value.id
  }

  # These domains have been dark for years. Full sampling costs almost nothing at
  # this traffic level and is the difference between seeing that a request
  # reached the load balancer during cutover and guessing.
  log_config {
    enable      = true
    sample_rate = 1.0
  }

  # A Cloud Armor rate limit would attach here, as security_policy on the backend
  # service, not on the URL map. Out of scope for this change.
}
