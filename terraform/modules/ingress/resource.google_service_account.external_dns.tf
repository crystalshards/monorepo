# GCP Service Account for external-dns
resource "google_service_account" "external_dns" {
  account_id   = "external-dns"
  display_name = "External DNS Service Account"
  description  = "Service account for external-dns to manage Cloud DNS records"
  project      = var.project_id
}

# Grant DNS Admin role to the service account
resource "google_project_iam_member" "external_dns_dns_admin" {
  project = var.project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.external_dns.email}"
}

# Bind GCP service account to Kubernetes service account via Workload Identity
resource "google_service_account_iam_member" "external_dns_workload_identity" {
  service_account_id = google_service_account.external_dns.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[infrastructure/external-dns]"
}
