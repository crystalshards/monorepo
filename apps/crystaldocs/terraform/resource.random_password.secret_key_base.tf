# Generate secure SECRET_KEY_BASE for Lucky framework
resource "random_password" "crystaldocs_secret_key_base" {
  length  = 128
  special = false # Hex characters only (a-f, 0-9)
}
