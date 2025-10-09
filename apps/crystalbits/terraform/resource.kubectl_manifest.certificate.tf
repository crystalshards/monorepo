# Certificate for crystalbits.org
# This certificate will be used by the Gateway API Gateway
resource "kubectl_manifest" "crystalbits_certificate" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "crystalbits-tls"
      namespace = kubernetes_namespace.crystalbits.metadata[0].name
    }
    spec = {
      secretName = "crystalbits-tls"
      issuerRef = {
        name = "letsencrypt-prod"
        kind = "ClusterIssuer"
      }
      dnsNames = [
        "crystalbits.org",
        "www.crystalbits.org"
      ]
    }
  })
}
