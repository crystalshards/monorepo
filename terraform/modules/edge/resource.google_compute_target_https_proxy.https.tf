resource "google_compute_target_https_proxy" "https" {
  project = var.project_id
  name    = "${var.name_prefix}-https"
  url_map = google_compute_url_map.https.id

  # Iterating the hostname set yields a stable lexical order, so this list does
  # not churn between plans. A target HTTPS proxy accepts up to 15 certificates
  # and this attaches 8.
  ssl_certificates = [
    for host in local.hostnames : google_compute_managed_ssl_certificate.host[host].id
  ]

  # ssl_policy is unset, so this uses the Google default policy, which still
  # permits TLS 1.0. Tightening it needs a google_compute_ssl_policy and is a
  # separate change from standing the edge up.
}
