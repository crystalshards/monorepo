# Ingress for crystalbits.org
resource "kubernetes_ingress_v1" "crystalbits" {
  metadata {
    name      = "crystalbits-ingress"
    namespace = kubernetes_namespace.crystalbits.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"                = "nginx"
      "external-dns.alpha.kubernetes.io/hostname" = "crystalbits.org,www.crystalbits.org"
      "cert-manager.io/cluster-issuer"            = "letsencrypt-prod"
    }
  }

  spec {
    tls {
      hosts = [
        "crystalbits.org",
        "www.crystalbits.org"
      ]
      secret_name = "crystalbits-tls"
    }

    rule {
      host = "crystalbits.org"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "crystalbits-service"
              port {
                number = 80
              }
            }
          }
        }
      }
    }

    rule {
      host = "www.crystalbits.org"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "crystalbits-service"
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
    kubernetes_namespace.crystalbits
  ]
}
