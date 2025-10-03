# Ingress for crystalshards.org
resource "kubernetes_ingress_v1" "crystalshards" {
  metadata {
    name      = "crystalshards-ingress"
    namespace = kubernetes_namespace.crystalshards.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"                = "nginx"
      "external-dns.alpha.kubernetes.io/hostname" = "crystalshards.org,www.crystalshards.org"
      "cert-manager.io/cluster-issuer"            = "letsencrypt-prod"
    }
  }

  spec {
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
              name = "crystalshards-service"
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
              name = "crystalshards-service"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.nginx_ingress,
    helm_release.external_dns,
    kubernetes_namespace.crystalshards
  ]
}
