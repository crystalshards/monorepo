# Let's Encrypt production cluster issuer for SSL certificates
# Supports both Ingress (nginx) and Gateway API (envoy-gateway)
resource "kubectl_manifest" "letsencrypt_prod" {
  yaml_body = <<-YAML
    apiVersion: cert-manager.io/v1
    kind: ClusterIssuer
    metadata:
      name: letsencrypt-prod
    spec:
      acme:
        server: https://acme-v02.api.letsencrypt.org/directory
        email: admin@crystalshards.org
        privateKeySecretRef:
          name: letsencrypt-prod-account-key
        solvers:
        # HTTP-01 solver for Ingress (legacy support during migration)
        - http01:
            ingress:
              class: nginx
        # HTTP-01 solver for Gateway API
        - http01:
            gatewayHTTPRoute:
              parentRefs:
              - name: crystalshards-gateway
                namespace: envoy-gateway-system
                kind: Gateway
  YAML

  depends_on = [
    helm_release.cert_manager
  ]
}
