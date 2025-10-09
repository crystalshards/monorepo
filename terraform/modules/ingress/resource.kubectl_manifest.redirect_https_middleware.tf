# HTTP to HTTPS redirect middleware
resource "kubectl_manifest" "redirect_https_middleware" {
  yaml_body = <<-YAML
    apiVersion: traefik.io/v1alpha1
    kind: Middleware
    metadata:
      name: redirect-https
      namespace: traefik-system
    spec:
      redirectScheme:
        scheme: https
        permanent: true
  YAML

  depends_on = [
    helm_release.traefik
  ]
}
