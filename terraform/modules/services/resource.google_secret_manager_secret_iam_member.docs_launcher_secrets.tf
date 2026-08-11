# docs-launcher's own secret grants, kept in a separate resource from the
# application ones so the dependency graph stays acyclic. See the comment on
# local.service_secret_accessors.
resource "google_secret_manager_secret_iam_member" "docs_launcher_secrets" {
  for_each = local.docs_launcher_secret_accessors

  project   = var.project_id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = each.value.member
}
