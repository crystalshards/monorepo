# Ingress for crystalgigs.com
resource "kubernetes_ingress_v1" "crystalgigs" {
  metadata {
    name      = "crystalgigs-ingress"
    namespace = kubernetes_namespace.crystalgigs.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"               = "nginx"
      "external-dns.alpha.kubernetes.io/hostname" = "crystalgigs.com,www.crystalgigs.com"
      "cert-manager.io/cluster-issuer"            = "letsencrypt-prod"
    }
  }

  spec {
    tls {
      hosts = [
        "crystalgigs.com",
        "www.crystalgigs.com"
      ]
      secret_name = "crystalgigs-tls"
    }

    rule {
      host = "crystalgigs.com"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "crystalgigs-service"
              port {
                number = 80
              }
            }
          }
        }
      }
    }

    rule {
      host = "www.crystalgigs.com"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "crystalgigs-service"
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
    kubernetes_namespace.crystalgigs
  ]
}
