# HTTPRoute for crystalgigs.com
# Replaces the Ingress resource with Gateway API HTTPRoute
resource "kubectl_manifest" "crystalgigs_httproute" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "crystalgigs-route"
      namespace = kubernetes_namespace.crystalgigs.metadata[0].name
      annotations = {
        "external-dns.alpha.kubernetes.io/hostname" = "crystalgigs.com,www.crystalgigs.com"
      }
    }
    spec = {
      parentRefs = [
        {
          name      = "crystalshards-gateway"
          namespace = "envoy-gateway-system"
          sectionName = "https-crystalgigs"
        },
        {
          name      = "crystalshards-gateway"
          namespace = "envoy-gateway-system"
          sectionName = "https-www-crystalgigs"
        }
      ]
      hostnames = [
        "crystalgigs.com",
        "www.crystalgigs.com"
      ]
      rules = [
        {
          matches = [
            {
              path = {
                type  = "PathPrefix"
                value = "/"
              }
            }
          ]
          backendRefs = [
            {
              name = kubernetes_service.crystalgigs.metadata[0].name
              port = 80
            }
          ]
        }
      ]
    }
  })
}

# HTTP to HTTPS redirect for crystalgigs.com
resource "kubectl_manifest" "crystalgigs_http_redirect" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "crystalgigs-http-redirect"
      namespace = kubernetes_namespace.crystalgigs.metadata[0].name
    }
    spec = {
      parentRefs = [
        {
          name      = "crystalshards-gateway"
          namespace = "envoy-gateway-system"
          sectionName = "http"
        }
      ]
      hostnames = [
        "crystalgigs.com",
        "www.crystalgigs.com"
      ]
      rules = [
        {
          filters = [
            {
              type = "RequestRedirect"
              requestRedirect = {
                scheme     = "https"
                statusCode = 301
              }
            }
          ]
        }
      ]
    }
  })
}
