# Shared Redis cluster for sessions and JoobQ
resource "kubectl_manifest" "shared_redis" {
  yaml_body = <<-YAML
    apiVersion: redis.redis.opstreelabs.in/v1beta1
    kind: Redis
    metadata:
      name: shared-redis
      namespace: ${kubernetes_namespace.infrastructure.metadata[0].name}
    spec:
      kubernetesConfig:
        image: redis:7-alpine
        imagePullPolicy: IfNotPresent
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"
        service:
          type: ClusterIP
      storage:
        volumeClaimTemplate:
          spec:
            accessModes: ["ReadWriteOnce"]
            resources:
              requests:
                storage: 5Gi
            storageClassName: standard-rwo
      redisConfig:
        maxmemory: "256mb"
        maxmemory-policy: "allkeys-lru"
  YAML

  depends_on = [helm_release.redis_operator]
}
