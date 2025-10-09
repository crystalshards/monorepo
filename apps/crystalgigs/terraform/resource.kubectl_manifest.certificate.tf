# Certificate for crystalgigs.com
# This certificate will be used by the Gateway API Gateway
resource "kubectl_manifest" "crystalgigs_certificate" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "crystalgigs-tls"
      namespace = kubernetes_namespace.crystalgigs.metadata[0].name
    }
    spec = {
      secretName = "crystalgigs-tls"
      issuerRef = {
        name = "letsencrypt-prod"
        kind = "ClusterIssuer"
      }
      dnsNames = [
        "crystalgigs.com",
        "www.crystalgigs.com"
      ]
    }
  })
}
