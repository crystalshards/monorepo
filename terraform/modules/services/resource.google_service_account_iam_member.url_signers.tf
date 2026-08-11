# Self binding that makes keyless V4 URL signing possible.
#
# Signing a URL normally needs the service account's private key. No key exists
# in this design and none should, so the signers call the IAM Credentials
# signBlob API against their own identity instead, which requires
# roles/iam.serviceAccountTokenCreator on themselves. This is the binding that
# makes "no service account keys anywhere" a workable position rather than an
# aspiration.
resource "google_service_account_iam_member" "url_signers" {
  for_each = local.url_signers

  service_account_id = "projects/${var.project_id}/serviceAccounts/${each.value}"
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${each.value}"
}
