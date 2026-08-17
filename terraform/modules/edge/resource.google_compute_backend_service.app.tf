# One backend service per app, each fronting that app's serverless NEG.
#
# No health check is attached: serverless NEG backends do not take one, because
# Cloud Run reports its own readiness and the load balancer has nothing to probe.
resource "google_compute_backend_service" "app" {
  # Keyed on local.services, the same static map the NEGs iterate, NOT on the
  # NEG resource itself. Iterating the resource looks equivalent and reads more
  # directly, but its keys are only known after apply, so terraform refuses the
  # whole configuration with
  #   Invalid for_each argument ... will be known only after apply
  # on any plan, apply or import. `terraform validate` does not evaluate
  # for_each, so this passed every check we had and failed the first real apply.
  for_each = local.services

  project = var.project_id
  name    = "${var.name_prefix}-${each.key}"

  # EXTERNAL_MANAGED is the global external Application Load Balancer. The
  # forwarding rules below must use the same scheme, the two cannot be mixed.
  load_balancing_scheme = "EXTERNAL_MANAGED"
  protocol              = "HTTP"

  backend {
    group = google_compute_region_network_endpoint_group.app[each.key].id
  }

  # What the apps' page view collector reads, and the only trustworthy source
  # for either fact.
  #
  # The balancer expands these variables from the connection it terminated and
  # OVERWRITES any header of the same name the client sent, so neither can be
  # spoofed from the internet. That is why the collector reads its own header
  # rather than X-Forwarded-For, whose earlier entries are client supplied, and
  # rather than the socket peer, which behind this balancer is the balancer.
  #
  # Without these two the collector still runs and still records, which is the
  # dangerous part: every visitor would hash against the same proxy address, so
  # the visitor count would collapse to one per day and every country would
  # read as unknown, with nothing anywhere reporting an error. The headers are
  # the feature, not a detail of it.
  #
  # client_region is a CLDR region code such as US or FR. When the balancer
  # cannot resolve one it expands to empty, which the collector records as
  # NULL rather than guessing from the address.
  custom_request_headers = [
    "X-Client-IP:{client_ip_address}",
    "X-Client-Geo-Location:{client_region}",
  ]

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
