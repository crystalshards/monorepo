# Generate secure random password for GitHub webhook secret
# Used to verify webhook signatures from GitHub
resource "random_password" "crystalshards_github_webhook_secret" {
  length  = 64
  special = true
}
