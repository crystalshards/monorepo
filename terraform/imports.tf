# Import blocks for existing resources
# These will import existing GCP resources into Terraform state

# Import existing Artifact Registry repository
import {
  to = module.cluster.google_artifact_registry_repository.docker_images
  id = "projects/crystalshards-org/locations/us/repositories/crystalshards"
}

# Import VPC network
import {
  to = module.networking.google_compute_network.vpc
  id = "projects/crystalshards-org/global/networks/crystalshards-cluster-vpc"
}

# Import subnet
import {
  to = module.networking.google_compute_subnetwork.subnet
  id = "projects/crystalshards-org/regions/us-central1/subnetworks/crystalshards-cluster-subnet"
}

# Import router
import {
  to = module.networking.google_compute_router.router
  id = "projects/crystalshards-org/regions/us-central1/routers/crystalshards-cluster-router"
}

# Import NAT gateway
import {
  to = module.networking.google_compute_router_nat.nat
  id = "crystalshards-org/us-central1/crystalshards-cluster-router/crystalshards-cluster-nat"
}

# Import enabled API
import {
  to = module.cluster.google_project_service.artifact_registry_api
  id = "crystalshards-org/artifactregistry.googleapis.com"
}

# Import firewall rules
import {
  to = module.networking.google_compute_firewall.allow_http_https
  id = "projects/crystalshards-org/global/firewalls/crystalshards-cluster-allow-http-https"
}

import {
  to = module.networking.google_compute_firewall.allow_internal
  id = "projects/crystalshards-org/global/firewalls/crystalshards-cluster-allow-internal"
}

import {
  to = module.networking.google_compute_firewall.allow_webhooks
  id = "projects/crystalshards-org/global/firewalls/crystalshards-cluster-allow-webhooks"
}

# Import claude namespace (agent namespace)
import {
  to = module.agent.kubernetes_namespace.claude
  id = "claude"
}
