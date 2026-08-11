# One serverless NEG per Cloud Run service.
#
# Serverless NEGs are regional and must live in the same region as the service
# they name, even though the load balancer in front of them is global.
resource "google_compute_region_network_endpoint_group" "app" {
  for_each = local.services

  project               = var.project_id
  name                  = "${var.name_prefix}-${each.key}"
  region                = var.region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = each.value
  }
}
