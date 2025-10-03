# Wait for cert-manager CRDs to be registered
resource "time_sleep" "wait_for_cert_manager" {
  depends_on = [helm_release.cert_manager]

  create_duration = "30s"
}
