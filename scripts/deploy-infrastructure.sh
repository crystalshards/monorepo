#!/bin/bash

# CrystalShards Infrastructure Deployment Script
# This script deploys the complete Kubernetes infrastructure

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if kubectl is configured
if ! kubectl cluster-info > /dev/null 2>&1; then
    print_error "kubectl is not configured or cluster is not accessible"
    print_error "Please run: gcloud container clusters get-credentials crystalshards-cluster --region us-central1 --project YOUR_PROJECT_ID"
    exit 1
fi

print_status "Starting infrastructure deployment..."

# 1. Deploy infrastructure namespace and operators (done by Terraform)
print_status "Verifying Terraform-deployed components..."

# Wait for operators to be ready
print_status "Waiting for operators to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/cnpg-controller-manager -n infrastructure || true
kubectl wait --for=condition=available --timeout=300s deployment/redis-operator -n infrastructure || true

# 2. Deploy PostgreSQL cluster
print_status "Deploying PostgreSQL cluster..."
kubectl apply -f kubernetes/infrastructure/postgresql-cluster.yaml

# Wait for PostgreSQL to be ready
print_status "Waiting for PostgreSQL cluster to be ready..."
kubectl wait --for=condition=Ready --timeout=600s cluster/postgresql-cluster -n infrastructure

# 3. Deploy Redis cluster
print_status "Deploying Redis cluster..."
kubectl apply -f kubernetes/infrastructure/redis-cluster.yaml

# Wait for Redis to be ready
print_status "Waiting for Redis to be ready..."
sleep 30
kubectl wait --for=condition=available --timeout=300s deployment -l app=redis-cluster -n infrastructure || true

# 4. Deploy MinIO tenant
print_status "Deploying MinIO tenant..."
kubectl apply -f kubernetes/infrastructure/minio-tenant.yaml

# Wait for MinIO to be ready
print_status "Waiting for MinIO to be ready..."
sleep 60
kubectl wait --for=condition=available --timeout=600s deployment -l v1.min.io/tenant=minio-tenant -n infrastructure || true

# 5. Run MinIO bucket setup job
print_status "Setting up MinIO buckets..."
kubectl delete job minio-bucket-setup -n infrastructure --ignore-not-found=true
kubectl apply -f kubernetes/infrastructure/minio-tenant.yaml
kubectl wait --for=condition=complete --timeout=300s job/minio-bucket-setup -n infrastructure

# 6. Deploy KEDA scaling configurations
print_status "Deploying KEDA autoscaling configurations..."
kubectl apply -f kubernetes/apps/keda-scaling.yaml

print_status "Infrastructure deployment completed!"

# Display connection information
print_status "Connection Information:"
echo "PostgreSQL: postgresql-service.infrastructure.svc.cluster.local:5432"
echo "Redis: redis-service.infrastructure.svc.cluster.local:6379"  
echo "MinIO: minio-service.infrastructure.svc.cluster.local:9000"

# Display credentials
print_status "Default Credentials (change in production):"
echo "PostgreSQL: crystalshards / crystal_dev_pass"
echo "MinIO: minioadmin / crystalshards-minio-2023"

print_warning "Remember to:"
echo "1. Change default passwords in production"
echo "2. Configure proper backup credentials"
echo "3. Set up SSL certificates"
echo "4. Configure monitoring alerts"

print_status "Infrastructure is ready for application deployment!"