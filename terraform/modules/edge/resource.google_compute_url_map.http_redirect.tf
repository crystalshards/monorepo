# The entire port 80 frontend: redirect to HTTPS, nothing else.
#
# No host_redirect is set, so the requested host is preserved. A www hostname
# therefore takes two hops, http://www.example.org to https://www.example.org to
# https://example.org, the second being the www rule in the HTTPS URL map.
resource "google_compute_url_map" "http_redirect" {
  project = var.project_id
  name    = "${var.name_prefix}-http-redirect"

  default_url_redirect {
    https_redirect         = true
    strip_query            = false
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
  }
}
