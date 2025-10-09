# HTTPRoute for crystalbits.org
# Replaces the Ingress resource with Gateway API HTTPRoute
resource "kubectl_manifest" "crystalbits_httproute" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "crystalbits-route"
      namespace = kubernetes_namespace.crystalbits.metadata[0].name
      annotations = {
        "external-dns.alpha.kubernetes.io/hostname" = "crystalbits.org,www.crystalbits.org"
      }
    }
    spec = {
      parentRefs = [
        {
          name      = "crystalshards-gateway"
          namespace = "envoy-gateway-system"
          sectionName = "https-crystalbits"
        },
        {
          name      = "crystalshards-gateway"
          namespace = "envoy-gateway-system"
          sectionName = "https-www-crystalbits"
        }
      ]
      hostnames = [
        "crystalbits.org",
        "www.crystalbits.org"
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
              name = kubernetes_service.crystalbits.metadata[0].name
              port = 80
            }
          ]
        }
      ]
    }
  })
}

# HTTP to HTTPS redirect for crystalbits.org
resource "kubectl_manifest" "crystalbits_http_redirect" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "crystalbits-http-redirect"
      namespace = kubernetes_namespace.crystalbits.metadata[0].name
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
        "crystalbits.org",
        "www.crystalbits.org"
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
