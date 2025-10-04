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

output "keda_installed" {
  description = "Whether KEDA is installed"
  value       = helm_release.keda.status == "deployed"
}
