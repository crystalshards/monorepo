output "cert_manager_installed" {
  description = "Whether cert-manager is installed"
  value       = helm_release.cert_manager.status == "deployed"
}

output "cnpg_installed" {
  description = "Whether CloudNativePG operator is installed"
  value       = helm_release.cnpg.status == "deployed"
}

output "redis_operator_installed" {
  description = "Whether Redis operator is installed"
  value       = helm_release.redis_operator.status == "deployed"
}

output "opentelemetry_operator_installed" {
  description = "Whether OpenTelemetry operator is installed"
  value       = helm_release.opentelemetry_operator.status == "deployed"
}

output "eck_operator_installed" {
  description = "Whether ECK operator is installed"
  value       = helm_release.eck_operator.status == "deployed"
}
