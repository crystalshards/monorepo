# Infrastructure namespace for cluster operators
resource "kubernetes_namespace" "infrastructure" {
  metadata {
    name = "infrastructure"
    labels = {
      name = "infrastructure"
    }
  }
}
