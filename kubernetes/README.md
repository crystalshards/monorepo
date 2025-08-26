# CrystalShards Kubernetes Manifests

This directory contains all Kubernetes manifests for the CrystalShards platform infrastructure and applications.

## Directory Structure

```
kubernetes/
├── infrastructure/          # Database, cache, and storage operators
│   ├── postgresql-cluster.yaml  # CloudNativePG PostgreSQL cluster
│   ├── redis-cluster.yaml      # Redis operator cluster
│   └── minio-tenant.yaml       # MinIO object storage tenant
├── apps/                   # Application-specific configurations  
│   └── keda-scaling.yaml   # KEDA autoscaling configurations
└── README.md
```

## Infrastructure Components

### PostgreSQL (CloudNativePG)
- **High Availability**: 3-node cluster with automatic failover
- **Resources**: 512Mi-1Gi memory, 250m-500m CPU per instance
- **Storage**: 20Gi per instance with standard storage class
- **Backups**: 7-day retention with cloud storage integration
- **Extensions**: pg_trgm, btree_gin, unaccent for search functionality

### Redis (Redis Operator)
- **Deployment**: Single instance + 3-node cluster for HA
- **Resources**: 128Mi-512Mi memory, 50m-200m CPU
- **Storage**: 5Gi for main instance, 2Gi per cluster node
- **Configuration**: Optimized for caching with LRU eviction
- **Monitoring**: Redis exporter for metrics

### MinIO (MinIO Operator)
- **Deployment**: 2-server, 2-volume setup for redundancy
- **Resources**: 512Mi-1Gi memory, 100m-500m CPU per server
- **Storage**: 10Gi per volume (20Gi total per server)
- **Buckets**: Pre-configured for registry, docs, gigs, and backups
- **Security**: Private access with bucket-level policies

## Autoscaling with KEDA

All applications are configured with KEDA for scale-to-zero capabilities:

### Scaling Triggers
- **HTTP Requests**: Scale based on incoming request rate
- **CPU/Memory**: Fallback triggers for resource utilization
- **Redis Queue**: Scale workers based on job queue length

### Scale Configuration
- **Registry**: 0-10 replicas, 5-minute cooldown
- **Docs**: 0-8 replicas, 5-minute cooldown  
- **Gigs**: 0-5 replicas, 10-minute cooldown
- **Worker**: 0-20 replicas, 1-minute cooldown

## Deployment

### Prerequisites
1. GKE cluster deployed via Terraform
2. kubectl configured for cluster access
3. All operators installed (KEDA, CloudNativePG, Redis, MinIO)

### Manual Deployment
```bash
# Deploy infrastructure components
kubectl apply -f infrastructure/

# Wait for databases to be ready
kubectl wait --for=condition=Ready cluster/postgresql-cluster -n infrastructure
kubectl wait --for=condition=available deployment -l app=redis-cluster -n infrastructure

# Deploy autoscaling configurations
kubectl apply -f apps/keda-scaling.yaml
```

### Automated Deployment
```bash
# Use the deployment script for full automation
./scripts/deploy-infrastructure.sh
```

## Monitoring

### Metrics Collection
- **PostgreSQL**: Built-in metrics via CloudNativePG
- **Redis**: Redis exporter for detailed metrics
- **MinIO**: Prometheus endpoint for storage metrics
- **KEDA**: Autoscaling metrics and events

### Service Monitoring
All services include ServiceMonitor configurations for Prometheus:
- Database performance and availability
- Cache hit rates and memory usage
- Storage capacity and request patterns
- Autoscaling events and replica counts

## Security

### Network Policies
- Namespace isolation with explicit allow rules
- Infrastructure services only accessible from app namespaces
- External traffic only through ingress controller

### Access Control
- Service accounts with minimal required permissions  
- Secrets for database credentials and object storage
- Workload Identity for GCP service integration

## Cost Optimization

### Resource Limits
All components have appropriate resource limits:
- **Requests**: Conservative estimates for cost predictability
- **Limits**: Prevent resource starvation and node overcommit
- **Storage**: Right-sized for expected data growth

### Scale-to-Zero
KEDA ensures applications scale down to zero when idle:
- **Idle Detection**: 5-10 minute windows before scale-down
- **Cold Start**: < 30 seconds to scale up from zero
- **Cost Savings**: 60-80% reduction during off-peak hours

## Troubleshooting

### Common Issues

#### PostgreSQL Not Ready
```bash
kubectl describe cluster postgresql-cluster -n infrastructure
kubectl logs -l cnpg.io/cluster=postgresql-cluster -n infrastructure
```

#### Redis Connection Issues
```bash
kubectl get redis redis-cluster -n infrastructure -o yaml
kubectl logs -l app=redis-cluster -n infrastructure
```

#### MinIO Access Problems
```bash
kubectl describe tenant minio-tenant -n infrastructure
kubectl logs -l v1.min.io/tenant=minio-tenant -n infrastructure
```

#### KEDA Not Scaling
```bash
kubectl get scaledobject -A
kubectl describe scaledobject crystalshards-registry-scaler -n crystalshards
kubectl logs -l app=keda-operator -n keda-system
```

### Health Checks

```bash
# Check all infrastructure components
kubectl get all -n infrastructure

# Verify KEDA is working
kubectl get scaledobject -A

# Check resource usage
kubectl top nodes
kubectl top pods -A
```

## Next Steps

After infrastructure deployment:
1. Deploy Crystal applications (`apps/*/`)  
2. Configure ingress and SSL certificates
3. Set up CI/CD pipelines
4. Configure monitoring alerts
5. Implement backup verification