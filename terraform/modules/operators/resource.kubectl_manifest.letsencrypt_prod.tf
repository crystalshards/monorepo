# Let's Encrypt production cluster issuer for SSL certificates
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
        - http01:
            ingress:
              class: nginx
  YAML

  depends_on = [
    helm_release.cert_manager
  ]
}
