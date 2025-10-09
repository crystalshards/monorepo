# Shared Gateway for all CrystalShards applications
# This replaces the NGINX Ingress Controller with Envoy Gateway
resource "kubectl_manifest" "gateway" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata = {
      name      = "crystalshards-gateway"
      namespace = "envoy-gateway-system"
      annotations = {
        # External DNS will manage DNS records for all domains
        "external-dns.alpha.kubernetes.io/hostname" = "crystalshards.org,www.crystalshards.org,crystaldocs.org,www.crystaldocs.org,crystalgigs.com,www.crystalgigs.com,crystalbits.org,www.crystalbits.org"
      }
    }
    spec = {
      gatewayClassName = "eg"
      listeners = [
        # HTTP listener (port 80) - will redirect to HTTPS
        {
          name     = "http"
          protocol = "HTTP"
          port     = 80
          allowedRoutes = {
            namespaces = {
              from = "All"
            }
          }
        },
        # HTTPS listener for crystalshards.org
        {
          name     = "https-crystalshards"
          protocol = "HTTPS"
          port     = 443
          hostname = "crystalshards.org"
          tls = {
            mode = "Terminate"
            certificateRefs = [
              {
                kind      = "Secret"
                name      = "crystalshards-tls"
                namespace = "crystalshards"
              }
            ]
          }
          allowedRoutes = {
            namespaces = {
              from = "All"
            }
          }
        },
        {
          name     = "https-www-crystalshards"
          protocol = "HTTPS"
          port     = 443
          hostname = "www.crystalshards.org"
          tls = {
            mode = "Terminate"
            certificateRefs = [
              {
                kind      = "Secret"
                name      = "crystalshards-tls"
                namespace = "crystalshards"
              }
            ]
          }
          allowedRoutes = {
            namespaces = {
              from = "All"
            }
          }
        },
        # HTTPS listener for crystaldocs.org
        {
          name     = "https-crystaldocs"
          protocol = "HTTPS"
          port     = 443
          hostname = "crystaldocs.org"
          tls = {
            mode = "Terminate"
            certificateRefs = [
              {
                kind      = "Secret"
                name      = "crystaldocs-tls"
                namespace = "crystaldocs"
              }
            ]
          }
          allowedRoutes = {
            namespaces = {
              from = "All"
            }
          }
        },
        {
          name     = "https-www-crystaldocs"
          protocol = "HTTPS"
          port     = 443
          hostname = "www.crystaldocs.org"
          tls = {
            mode = "Terminate"
            certificateRefs = [
              {
                kind      = "Secret"
                name      = "crystaldocs-tls"
                namespace = "crystaldocs"
              }
            ]
          }
          allowedRoutes = {
            namespaces = {
              from = "All"
            }
          }
        },
        # HTTPS listener for crystalgigs.com
        {
          name     = "https-crystalgigs"
          protocol = "HTTPS"
          port     = 443
          hostname = "crystalgigs.com"
          tls = {
            mode = "Terminate"
            certificateRefs = [
              {
                kind      = "Secret"
                name      = "crystalgigs-tls"
                namespace = "crystalgigs"
              }
            ]
          }
          allowedRoutes = {
            namespaces = {
              from = "All"
            }
          }
        },
        {
          name     = "https-www-crystalgigs"
          protocol = "HTTPS"
          port     = 443
          hostname = "www.crystalgigs.com"
          tls = {
            mode = "Terminate"
            certificateRefs = [
              {
                kind      = "Secret"
                name      = "crystalgigs-tls"
                namespace = "crystalgigs"
              }
            ]
          }
          allowedRoutes = {
            namespaces = {
              from = "All"
            }
          }
        },
        # HTTPS listener for crystalbits.org
        {
          name     = "https-crystalbits"
          protocol = "HTTPS"
          port     = 443
          hostname = "crystalbits.org"
          tls = {
            mode = "Terminate"
            certificateRefs = [
              {
                kind      = "Secret"
                name      = "crystalbits-tls"
                namespace = "crystalbits"
              }
            ]
          }
          allowedRoutes = {
            namespaces = {
              from = "All"
            }
          }
        },
        {
          name     = "https-www-crystalbits"
          protocol = "HTTPS"
          port     = 443
          hostname = "www.crystalbits.org"
          tls = {
            mode = "Terminate"
            certificateRefs = [
              {
                kind      = "Secret"
                name      = "crystalbits-tls"
                namespace = "crystalbits"
              }
            ]
          }
          allowedRoutes = {
            namespaces = {
              from = "All"
            }
          }
        }
      ]
    }
  })

  depends_on = [helm_release.envoy_gateway]
}
