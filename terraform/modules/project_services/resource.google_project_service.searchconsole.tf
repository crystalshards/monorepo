# Google Search Console API. The four sites read their own search performance
# from it once a day and store the rows in their own database, so the stats
# page can say what people searched for without talking to Google on render.
#
# The call is made with the Cloud Run service's ambient identity, the same way
# docs-launcher signs URLs: no key file exists anywhere in this path. Enabling
# the API grants nothing on its own. A service still reads exactly the one
# property a human added it to as a user in Search Console, which is not a
# terraform-manageable resource.
resource "google_project_service" "searchconsole" {
  project = var.project_id
  service = "searchconsole.googleapis.com"

  disable_on_destroy = var.disable_on_destroy
}
