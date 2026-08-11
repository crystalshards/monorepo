resource "google_secret_manager_secret_version" "sendgrid_key" {
  for_each = local.lucky_services

  secret      = google_secret_manager_secret.sendgrid_key[each.key].id
  secret_data = local.sendgrid_keys[each.key]
}
