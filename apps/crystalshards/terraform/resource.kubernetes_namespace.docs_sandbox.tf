# Dedicated namespace for untrusted documentation builds.
#
# This MUST stay a separate namespace from the main crystalshards namespace. The
# allow-infrastructure-access NetworkPolicy in the crystalshards namespace selects
# pod_selector {} (every pod in that namespace) and NetworkPolicies are additive
# (a union of allows), so any sandbox pod placed in the crystalshards namespace
# would inherit egress to 0.0.0.0/0:443 and could not be isolated. Only a
# separate namespace gives the docs-sandbox isolation policy a clean slate.
resource "kubernetes_namespace" "docs_sandbox" {
  metadata {
    name = "crystalshards-docs-sandbox"
    labels = {
      "app.kubernetes.io/name"    = "docs-sandbox"
      "app.kubernetes.io/part-of" = "crystalshards"
    }
  }
}
