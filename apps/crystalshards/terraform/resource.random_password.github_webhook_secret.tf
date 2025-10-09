# Random password for GitHub webhook secret
resource "random_password" "github_webhook_secret" {
  length  = 64
  special = true
}
