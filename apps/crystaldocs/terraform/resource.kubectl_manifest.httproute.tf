# HTTPRoute for crystaldocs.org
# Replaces the Ingress resource with Gateway API HTTPRoute
resource "kubectl_manifest" "crystaldocs_httproute" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "crystaldocs-route"
      namespace = kubernetes_namespace.crystaldocs.metadata[0].name
      annotations = {
        "external-dns.alpha.kubernetes.io/hostname" = "crystaldocs.org,www.crystaldocs.org"
      }
    }
    spec = {
      parentRefs = [
        {
          name      = "crystalshards-gateway"
          namespace = "envoy-gateway-system"
          sectionName = "https-crystaldocs"
        },
        {
          name      = "crystalshards-gateway"
          namespace = "envoy-gateway-system"
          sectionName = "https-www-crystaldocs"
        }
      ]
      hostnames = [
        "crystaldocs.org",
        "www.crystaldocs.org"
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
              name = kubernetes_service.crystaldocs.metadata[0].name
              port = 80
            }
          ]
        }
      ]
    }
  })
}

# HTTP to HTTPS redirect for crystaldocs.org
resource "kubectl_manifest" "crystaldocs_http_redirect" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "crystaldocs-http-redirect"
      namespace = kubernetes_namespace.crystaldocs.metadata[0].name
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
        "crystaldocs.org",
        "www.crystaldocs.org"
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
