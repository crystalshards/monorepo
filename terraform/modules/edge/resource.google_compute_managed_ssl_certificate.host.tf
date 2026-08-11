# One Google managed certificate per hostname, eight in total.
#
# Ordering that looks like a failure and is not: a managed certificate stays in
# PROVISIONING until the hostname on it resolves publicly to this load balancer.
# The DNS records that make that true are created by the same apply that creates
# these certificates, so the first apply necessarily finishes with every
# certificate still PROVISIONING. That is expected. HTTPS starts working once
# Google has seen the DNS and issued, without a further apply.
#
# One certificate per hostname rather than one certificate with eight SANs: a
# managed certificate only reaches ACTIVE when every domain on it validates, so a
# single eight name certificate lets one broken delegation hold all four sites
# hostage. Split this way, a hostname that fails to validate fails alone, and the
# deploy smoke test can resolve status per host.
resource "google_compute_managed_ssl_certificate" "host" {
  for_each = local.hostnames

  project = var.project_id
  name    = "${var.name_prefix}-${replace(each.key, ".", "-")}"

  managed {
    domains = [each.key]
  }

  # A managed certificate cannot be edited in place; any change to its domains
  # replaces it. Creating the replacement before dropping the old one keeps the
  # HTTPS proxy from briefly referencing a certificate that no longer exists.
  lifecycle {
    create_before_destroy = true
  }
}
