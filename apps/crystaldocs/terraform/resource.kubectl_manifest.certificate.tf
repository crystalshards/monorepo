# Certificate for crystaldocs.org
# This certificate will be used by the Gateway API Gateway
resource "kubectl_manifest" "crystaldocs_certificate" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "crystaldocs-tls"
      namespace = kubernetes_namespace.crystaldocs.metadata[0].name
    }
    spec = {
      secretName = "crystaldocs-tls"
      issuerRef = {
        name = "letsencrypt-prod"
        kind = "ClusterIssuer"
      }
      dnsNames = [
        "crystaldocs.org",
        "www.crystaldocs.org"
      ]
    }
  })
}
