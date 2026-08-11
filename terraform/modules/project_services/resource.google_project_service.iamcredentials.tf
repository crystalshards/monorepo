# IAM Service Account Credentials. docs-launcher signs V4 URLs with signBlob
# rather than a downloaded key, so this API is what makes a keyless signer
# possible at all. Without it the launcher cannot mint the signed GET and PUT
# that are the docs-build Job's only route to storage.
resource "google_project_service" "iamcredentials" {
  project = var.project_id
  service = "iamcredentials.googleapis.com"

  disable_on_destroy = var.disable_on_destroy
}
