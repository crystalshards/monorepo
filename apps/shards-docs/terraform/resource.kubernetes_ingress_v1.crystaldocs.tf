# Ingress for crystaldocs.org
resource "kubernetes_ingress_v1" "crystaldocs" {
  metadata {
    name      = "crystaldocs-ingress"
    namespace = kubernetes_namespace.crystaldocs.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"               = "nginx"
      "external-dns.alpha.kubernetes.io/hostname" = "crystaldocs.org,www.crystaldocs.org"
      "cert-manager.io/cluster-issuer"            = "letsencrypt-prod"
    }
  }

  spec {
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
              name = "crystaldocs-service"
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
              name = "crystaldocs-service"
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
    kubernetes_namespace.crystaldocs
  ]
}
