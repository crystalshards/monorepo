# ServiceAccount for docs build pods.
#
# automount_service_account_token = false: a compromised build must not be able
# to talk to the Kubernetes API server at all. The build pod runs untrusted
# compile-time macro code and has no legitimate reason to hold API credentials.
# (The worker that creates the Jobs authenticates with its OWN ServiceAccount in
# the crystalshards namespace; this account is only the identity the build pods
# run under.)
resource "kubernetes_service_account" "docs_sandbox" {
  metadata {
    name      = "docs-sandbox"
    namespace = kubernetes_namespace.docs_sandbox.metadata[0].name
    labels = {
      "app.kubernetes.io/name"    = "docs-sandbox"
      "app.kubernetes.io/part-of" = "crystalshards"
    }
  }

  automount_service_account_token = false
}
