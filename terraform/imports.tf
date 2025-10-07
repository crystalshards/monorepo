# Import blocks for existing resources
# These will import existing GCP resources into Terraform state
#
# NOTE: GKE cluster is intentionally NOT imported here.
# The existing cluster will be destroyed and recreated as Autopilot.
# All Kubernetes resources (namespaces, helm releases) will be recreated.
#
# IMPORTANT: Import blocks commented out because resources were cleaned up.
# Terraform will create fresh resources on next apply.
