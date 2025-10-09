# Certificate for crystalshards.org
# This certificate will be used by the Gateway API Gateway
resource "kubectl_manifest" "crystalshards_certificate" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "crystalshards-tls"
      namespace = kubernetes_namespace.crystalshards.metadata[0].name
    }
    spec = {
      secretName = "crystalshards-tls"
      issuerRef = {
        name = "letsencrypt-prod"
        kind = "ClusterIssuer"
      }
      dnsNames = [
        "crystalshards.org",
        "www.crystalshards.org"
      ]
    }
  })
}
