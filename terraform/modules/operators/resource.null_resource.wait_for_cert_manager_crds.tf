# Wait for cert-manager CRDs to be registered
resource "null_resource" "wait_for_cert_manager_crds" {
  depends_on = [helm_release.cert_manager]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<-EOT
      set -e
      echo "Waiting for cert-manager CRDs to be registered..."
      for i in $(seq 1 60); do
        if kubectl get crd clusterissuers.cert-manager.io >/dev/null 2>&1; then
          echo "cert-manager CRDs are ready!"
          exit 0
        fi
        echo "Waiting for CRDs... attempt $i/60"
        sleep 5
      done
      echo "ERROR: cert-manager CRDs not ready after 5 minutes"
      exit 1
    EOT
  }
}
