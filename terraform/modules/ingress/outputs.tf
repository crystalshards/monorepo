output "nginx_ingress_installed" {
  description = "Whether nginx-ingress is installed"
  value       = helm_release.nginx_ingress.status == "deployed"
}

output "external_dns_installed" {
  description = "Whether external-dns is installed"
  value       = helm_release.external_dns.status == "deployed"
}

output "load_balancer_ip_command" {
  description = "Command to get the load balancer IP"
  value       = "kubectl get service -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
}
