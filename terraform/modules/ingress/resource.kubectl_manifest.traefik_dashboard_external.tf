# External IngressRoute for Traefik dashboard
resource "kubectl_manifest" "traefik_dashboard_external" {
  yaml_body = yamlencode({
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "traefik-dashboard-external"
      namespace = "traefik-system"
      annotations = {
        "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
      }
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        kind  = "Rule"
        match = "Host(`traefik.crystalshards.org`)"
        services = [{
          kind = "TraefikService"
          name = "api@internal"
        }]
      }]
      tls = {
        secretName = "traefik-dashboard-tls"
      }
    }
  })

  depends_on = [helm_release.traefik]
}

# Certificate for Traefik dashboard
resource "kubectl_manifest" "traefik_dashboard_certificate" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "traefik-dashboard-tls"
      namespace = "traefik-system"
    }
    spec = {
      secretName = "traefik-dashboard-tls"
      issuerRef = {
        name = "letsencrypt-prod"
        kind = "ClusterIssuer"
      }
      dnsNames = ["traefik.crystalshards.org"]
    }
  })

  depends_on = [helm_release.traefik]
}
