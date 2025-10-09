output "envoy_gateway_installed" {
  description = "Whether Envoy Gateway is installed"
  value       = helm_release.envoy_gateway.status == "deployed"
}

output "external_dns_installed" {
  description = "Whether external-dns is installed"
  value       = helm_release.external_dns.status == "deployed"
}

output "load_balancer_ip_command" {
  description = "Command to get the load balancer IP"
  value       = "kubectl get service -n envoy-gateway-system envoy-crystalshards-gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
}

output "gateway_status_command" {
  description = "Command to check Gateway status"
  value       = "kubectl get gateway crystalshards-gateway -n envoy-gateway-system"
}
