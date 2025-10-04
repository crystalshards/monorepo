# Root outputs - aggregates outputs from all modules

# Cluster outputs
output "cluster_name" {
  description = "GKE cluster name"
  value       = module.cluster.cluster_name
}

output "cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = module.cluster.cluster_endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "GKE cluster CA certificate"
  value       = module.cluster.cluster_ca_certificate
  sensitive   = true
}

output "kubectl_config" {
  description = "kubectl configuration command"
  value       = module.cluster.kubectl_config_command
}

# Networking outputs
output "vpc_network" {
  description = "VPC network name"
  value       = module.networking.network_name
}

output "subnet_name" {
  description = "Subnet name"
  value       = module.networking.subnet_name
}

# Ingress outputs
output "load_balancer_ip_command" {
  description = "Command to get the load balancer IP"
  value       = module.ingress.load_balancer_ip_command
}

# Application outputs
output "namespaces" {
  description = "Created Kubernetes namespaces"
  value       = module.applications.namespaces
}

# General outputs
output "region" {
  description = "GCP region"
  value       = var.region
}

output "project_id" {
  description = "GCP project ID"
  value       = var.project_id
}

# Operator status
output "operators_installed" {
  description = "Status of installed operators"
  value = {
    cert_manager  = module.operators.cert_manager_installed
    cnpg          = module.operators.cnpg_installed
    redis         = module.operators.redis_operator_installed
    keda          = module.operators.keda_installed
    opentelemetry = module.operators.opentelemetry_operator_installed
    eck           = module.operators.eck_operator_installed
  }
}
