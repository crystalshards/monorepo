# Host based routing for the HTTPS frontend.
#
# Apex hostnames are served by their app's backend. www hostnames are redirected
# to the apex rather than served, so each site has exactly one origin and one
# canonical URL, and there is no duplicate content to keep consistent.
#
# Every host rule below comes from var.sites, the same value that produces the
# certificates and the DNS records, so a hostname cannot be routed here but
# missing from those, or present there and unroutable here.
resource "google_compute_url_map" "https" {
  project = var.project_id
  name    = "${var.name_prefix}-https"

  # Requests whose Host matches nothing configured, for example a request sent
  # straight to the load balancer IP, are redirected to the flagship apex. There
  # is no backend that could sensibly answer for an unknown host.
  default_url_redirect {
    host_redirect          = var.sites[var.default_site].apex
    https_redirect         = true
    strip_query            = false
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
  }

  dynamic "host_rule" {
    for_each = var.sites
    content {
      hosts        = [host_rule.value.apex]
      path_matcher = "serve-${host_rule.key}"
    }
  }

  dynamic "path_matcher" {
    for_each = var.sites
    content {
      name            = "serve-${path_matcher.key}"
      default_service = google_compute_backend_service.app[path_matcher.key].id
    }
  }

  dynamic "host_rule" {
    for_each = var.sites
    content {
      hosts        = [host_rule.value.www]
      path_matcher = "redirect-${host_rule.key}"
    }
  }

  # www to apex. Path is preserved because no path_redirect or prefix_redirect is
  # set, and the query string is preserved because strip_query is false, so
  # https://www.example.org/a?b=c lands on https://example.org/a?b=c.
  dynamic "path_matcher" {
    for_each = var.sites
    content {
      name = "redirect-${path_matcher.key}"
      default_url_redirect {
        host_redirect          = path_matcher.value.apex
        https_redirect         = true
        strip_query            = false
        redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
      }
    }
  }
}
