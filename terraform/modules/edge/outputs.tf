output "load_balancer_ip" {
  description = "Global anycast IPv4 address every public hostname resolves to. This is the value modules/dns writes into the A records."
  value       = google_compute_global_address.lb.address
}

output "public_hostnames" {
  description = "All eight public hostnames, apex and www for each site, in stable order."
  value       = sort(tolist(local.hostnames))
}

output "managed_certificates" {
  description = "Hostname to managed certificate name. One certificate per hostname, so live status can be read per host with `gcloud compute ssl-certificates describe <name> --global`."
  value       = { for host, cert in google_compute_managed_ssl_certificate.host : host => cert.name }
}

output "backend_service_names" {
  description = "Site key to backend service name, for attaching a Cloud Armor policy or reading load balancer logs per app."
  value       = { for slug, backend in google_compute_backend_service.app : slug => backend.name }
}
