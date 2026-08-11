# Consumed by the deploy smoke test. Kept out of outputs.tf so the edge work and
# the Kubernetes teardown do not edit the same file.
output "load_balancer_ip" {
  description = "Global anycast IPv4 address all eight public hostnames resolve to."
  value       = module.edge.load_balancer_ip
}

output "public_hostnames" {
  description = "All eight public hostnames, apex and www for each of the four sites."
  value       = module.edge.public_hostnames
}

output "managed_certificates" {
  description = "Hostname to Google managed certificate name, one certificate per hostname."
  value       = module.edge.managed_certificates
}
