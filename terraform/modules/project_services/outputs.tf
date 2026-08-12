output "enabled_services" {
  description = "Every API this module turns on, so a dependent module can prove its own prerequisite is in the list"
  value = [
    google_project_service.artifactregistry.service,
    google_project_service.certificatemanager.service,
    google_project_service.cloudresourcemanager.service,
    google_project_service.cloudscheduler.service,
    google_project_service.cloudtasks.service,
    google_project_service.compute.service,
    google_project_service.dns.service,
    google_project_service.iam.service,
    google_project_service.iamcredentials.service,
    google_project_service.run.service,
    google_project_service.secretmanager.service,
    google_project_service.sqladmin.service,
    google_project_service.storage.service,
  ]
}
