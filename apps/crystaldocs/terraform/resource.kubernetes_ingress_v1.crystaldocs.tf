# Ingress for crystaldocs.org
resource "kubernetes_ingress_v1" "crystaldocs" {
  metadata {
    name      = "crystaldocs-ingress"
    namespace = kubernetes_namespace.crystaldocs.metadata[0].name
    annotations = {
      "external-dns.alpha.kubernetes.io/hostname" = "crystaldocs.org,www.crystaldocs.org"
      "cert-manager.io/cluster-issuer"            = "letsencrypt-prod"
    }
  }

  spec {
    ingress_class_name = "traefik"

    tls {
      hosts = [
        "crystaldocs.org",
        "www.crystaldocs.org"
      ]
      secret_name = "crystaldocs-tls"
    }

    rule {
      host = "crystaldocs.org"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.crystaldocs.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }

    rule {
      host = "www.crystaldocs.org"
      http {
        path {
          path_type = "Prefix"
          path      = "/"
          backend {
            service {
              name = kubernetes_service.crystaldocs.metadata[0].name
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
