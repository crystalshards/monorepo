resource "google_secret_manager_secret_version" "secret_key_base" {
  for_each = local.lucky_services

  secret      = google_secret_manager_secret.secret_key_base[each.key].id
  secret_data = random_password.secret_key_base[each.key].result
}
