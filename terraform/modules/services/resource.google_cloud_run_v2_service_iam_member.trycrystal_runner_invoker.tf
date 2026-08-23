# The only principal that may invoke trycrystal-runner.
#
# The runner has ingress ALL because the trycrystal app reaches it over its
# public run.app URL (this stack has no VPC connector, so internal ingress
# would be unreachable from a sibling Cloud Run service), so this single
# binding is the entire access control on it. There is no allUsers grant, and
# adding one would turn an arbitrary code execution endpoint into an anonymous
# arbitrary code execution endpoint.
#
# The app presents an ID token minted by the metadata server for this, its own
# identity, carrying the audience the runner declares in custom_audiences.
# Neither the URL nor the audience alone reaches anything without the token,
# and nothing else in the project holds run.invoker on this service.
resource "google_cloud_run_v2_service_iam_member" "trycrystal_runner_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.trycrystal_runner.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.apps["trycrystal"].email}"
}
