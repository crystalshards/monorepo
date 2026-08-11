# Identity and Access Management. This is the API that serves
# google_service_account, so it gates the eleven identities this stack creates
# before it gates anything they do. It is commonly on already in a project that
# was made through the console, which is exactly why it is easy to leave out and
# then discover on the one project where it is not.
resource "google_project_service" "iam" {
  project = var.project_id
  service = "iam.googleapis.com"

  disable_on_destroy = var.disable_on_destroy
}
