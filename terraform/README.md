# CrystalShards Terraform Infrastructure

This Terraform configuration creates a cost-optimized GKE cluster with all necessary operators for running the CrystalShards platform.

## Architecture

- **GKE Cluster**: Autopilot-enabled cluster with scale-to-zero capabilities
- **Namespaces**: Isolated environments for each application
- **Operators**: In-cluster PostgreSQL, Redis, and MinIO for zero external dependencies
- **Autoscaling**: KEDA for HTTP-based scaling with idle scale-down
- **Monitoring**: Lightweight Prometheus stack
- **Networking**: Private cluster with NAT gateway

## Cost Optimization Features

- GKE Autopilot mode for pay-per-use pricing
- Preemptible nodes for additional savings
- Scale-to-zero with KEDA autoscaling
- Minimal resource requests and limits
- 7-day metric retention to reduce storage costs

## Setup

1. Copy the example variables file:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Edit `terraform.tfvars` with your GCP project details:
   ```hcl
   project_id = "your-project-id"
   region     = "us-central1"
   ```

3. Initialize and apply Terraform:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

4. Configure kubectl:
   ```bash
   gcloud container clusters get-credentials crystalshards-cluster --region us-central1 --project your-project-id
   ```

## Resource Estimates

With default settings (Autopilot + preemptible nodes):
- **Idle cost**: ~$50-100/month (when scaled to zero)
- **Active cost**: ~$200-400/month (under normal load)
- **Scaling**: Automatically scales from 0 to 50+ pods based on traffic

## Operators Included

- **KEDA**: HTTP-based autoscaling with scale-to-zero
- **CloudNativePG**: In-cluster PostgreSQL with backups
- **Redis Operator**: In-cluster Redis for caching
- **MinIO Operator**: In-cluster object storage
- **Prometheus**: Lightweight monitoring stack
- **Ingress NGINX**: Load balancer and SSL termination

## Security Features

- Private cluster with authorized networks
- Network policies for namespace isolation
- Workload Identity for secure GCP access
- Shielded GKE nodes
- VPC-native networking

## Namespaces

- `claude`: Development agent
- `crystalshards`: Main registry application
- `crystaldocs`: Documentation platform
- `crystalgigs`: Job board application
- `infrastructure`: Database and cache operators
- `keda-system`: Autoscaling controller
- `monitoring`: Prometheus and Grafana
- `ingress-nginx`: Load balancer

## Next Steps

After applying this Terraform configuration:

1. Deploy the database operators and instances
2. Set up GitHub Actions for CI/CD
3. Deploy the Crystal applications
4. Configure DNS and SSL certificates