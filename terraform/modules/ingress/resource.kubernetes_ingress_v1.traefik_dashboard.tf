# Ingress for Traefik dashboard
resource "kubernetes_ingress_v1" "traefik_dashboard" {
  metadata {
    name      = "traefik-dashboard"
    namespace = "traefik-system"
    annotations = {
      "cert-manager.io/cluster-issuer"                   = "letsencrypt-prod"
      "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
      "traefik.ingress.kubernetes.io/router.tls"         = "true"
    }
  }

  spec {
    ingress_class_name = "traefik"

    tls {
      hosts       = ["traefik.crystalshards.org"]
      secret_name = "traefik-dashboard-tls"
    }

    rule {
      host = "traefik.crystalshards.org"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "traefik"
              port {
                number = 9000
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.traefik]
}
