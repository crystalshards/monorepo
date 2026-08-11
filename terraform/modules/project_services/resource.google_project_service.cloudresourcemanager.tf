# Cloud Resource Manager. Serves the project level IAM policy, so it gates every
# google_project_iam_member, which here is the roles/cloudsql.client grant that
# nine identities depend on to open a database connection at all.
resource "google_project_service" "cloudresourcemanager" {
  project = var.project_id
  service = "cloudresourcemanager.googleapis.com"

  disable_on_destroy = var.disable_on_destroy
}
