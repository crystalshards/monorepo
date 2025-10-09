# Ingress for crystalshards.org
resource "kubernetes_ingress_v1" "crystalshards" {
  metadata {
    name      = "crystalshards-ingress"
    namespace = kubernetes_namespace.crystalshards.metadata[0].name
    annotations = {
      "external-dns.alpha.kubernetes.io/hostname"                   = "crystalshards.org,www.crystalshards.org"
      "cert-manager.io/cluster-issuer"                              = "letsencrypt-prod"
      "traefik.ingress.kubernetes.io/router.entrypoints"            = "web,websecure"
      "traefik.ingress.kubernetes.io/router.middlewares"            = "traefik-system-redirect-https@kubernetescrd"
    }
  }

  spec {
    ingress_class_name = "traefik"

    tls {
      hosts = [
        "crystalshards.org",
        "www.crystalshards.org"
      ]
      secret_name = "crystalshards-tls"
    }

    rule {
      host = "crystalshards.org"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.crystalshards.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }

    rule {
      host = "www.crystalshards.org"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.crystalshards.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

}
