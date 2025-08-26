output "cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.primary.name
}

output "cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "GKE cluster CA certificate"
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "vpc_network" {
  description = "VPC network name"
  value       = google_compute_network.vpc.name
}

output "subnet_name" {
  description = "Subnet name"
  value       = google_compute_subnetwork.subnet.name
}

output "region" {
  description = "GCP region"
  value       = var.region
}

output "project_id" {
  description = "GCP project ID"
  value       = var.project_id
}

output "kubectl_config" {
  description = "kubectl configuration command"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --region ${var.region} --project ${var.project_id}"
}

output "load_balancer_ip" {
  description = "External IP address of the load balancer"
  value       = helm_release.nginx_ingress.status[0].load_balancer[0].ingress[0].ip
}

output "namespaces" {
  description = "Created Kubernetes namespaces"
  value = {
    claude         = kubernetes_namespace.claude.metadata[0].name
    crystalshards  = kubernetes_namespace.crystalshards.metadata[0].name
    crystaldocs    = kubernetes_namespace.crystaldocs.metadata[0].name
    crystalgigs    = kubernetes_namespace.crystalgigs.metadata[0].name
    infrastructure = kubernetes_namespace.infrastructure.metadata[0].name
  }
}