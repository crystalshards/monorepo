# ReferenceGrants allow the Gateway in envoy-gateway-system namespace
# to reference TLS secrets in application namespaces

resource "kubectl_manifest" "reference_grant_crystalshards" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1beta1"
    kind       = "ReferenceGrant"
    metadata = {
      name      = "allow-gateway-tls"
      namespace = "crystalshards"
    }
    spec = {
      from = [
        {
          group     = "gateway.networking.k8s.io"
          kind      = "Gateway"
          namespace = "envoy-gateway-system"
        }
      ]
      to = [
        {
          group = ""
          kind  = "Secret"
          name  = "crystalshards-tls"
        }
      ]
    }
  })

  depends_on = [helm_release.envoy_gateway]
}

resource "kubectl_manifest" "reference_grant_crystaldocs" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1beta1"
    kind       = "ReferenceGrant"
    metadata = {
      name      = "allow-gateway-tls"
      namespace = "crystaldocs"
    }
    spec = {
      from = [
        {
          group     = "gateway.networking.k8s.io"
          kind      = "Gateway"
          namespace = "envoy-gateway-system"
        }
      ]
      to = [
        {
          group = ""
          kind  = "Secret"
          name  = "crystaldocs-tls"
        }
      ]
    }
  })

  depends_on = [helm_release.envoy_gateway]
}

resource "kubectl_manifest" "reference_grant_crystalgigs" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1beta1"
    kind       = "ReferenceGrant"
    metadata = {
      name      = "allow-gateway-tls"
      namespace = "crystalgigs"
    }
    spec = {
      from = [
        {
          group     = "gateway.networking.k8s.io"
          kind      = "Gateway"
          namespace = "envoy-gateway-system"
        }
      ]
      to = [
        {
          group = ""
          kind  = "Secret"
          name  = "crystalgigs-tls"
        }
      ]
    }
  })

  depends_on = [helm_release.envoy_gateway]
}

resource "kubectl_manifest" "reference_grant_crystalbits" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1beta1"
    kind       = "ReferenceGrant"
    metadata = {
      name      = "allow-gateway-tls"
      namespace = "crystalbits"
    }
    spec = {
      from = [
        {
          group     = "gateway.networking.k8s.io"
          kind      = "Gateway"
          namespace = "envoy-gateway-system"
        }
      ]
      to = [
        {
          group = ""
          kind  = "Secret"
          name  = "crystalbits-tls"
        }
      ]
    }
  })

  depends_on = [helm_release.envoy_gateway]
}
