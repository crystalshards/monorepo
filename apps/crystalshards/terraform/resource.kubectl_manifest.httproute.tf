# HTTPRoute for crystalshards.org
# Replaces the Ingress resource with Gateway API HTTPRoute
resource "kubectl_manifest" "crystalshards_httproute" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "crystalshards-route"
      namespace = kubernetes_namespace.crystalshards.metadata[0].name
      annotations = {
        "external-dns.alpha.kubernetes.io/hostname" = "crystalshards.org,www.crystalshards.org"
      }
    }
    spec = {
      parentRefs = [
        {
          name      = "crystalshards-gateway"
          namespace = "envoy-gateway-system"
          sectionName = "https-crystalshards"
        },
        {
          name      = "crystalshards-gateway"
          namespace = "envoy-gateway-system"
          sectionName = "https-www-crystalshards"
        }
      ]
      hostnames = [
        "crystalshards.org",
        "www.crystalshards.org"
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
              name = kubernetes_service.crystalshards.metadata[0].name
              port = 80
            }
          ]
        }
      ]
    }
  })
}

# HTTP to HTTPS redirect for crystalshards.org
resource "kubectl_manifest" "crystalshards_http_redirect" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "crystalshards-http-redirect"
      namespace = kubernetes_namespace.crystalshards.metadata[0].name
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
        "crystalshards.org",
        "www.crystalshards.org"
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
