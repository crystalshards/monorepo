# Shared MinIO tenant for package and doc storage
resource "kubectl_manifest" "shared_minio" {
  yaml_body = <<-YAML
    apiVersion: minio.min.io/v2
    kind: Tenant
    metadata:
      name: shared-storage
      namespace: ${kubernetes_namespace.infrastructure.metadata[0].name}
    spec:
      pools:
        - servers: 2
          name: pool-0
          volumesPerServer: 2
          volumeClaimTemplate:
            metadata:
              name: data
            spec:
              accessModes:
                - ReadWriteOnce
              resources:
                requests:
                  storage: 20Gi
              storageClassName: standard-rwo
          resources:
            requests:
              cpu: "250m"
              memory: "512Mi"
            limits:
              cpu: "1000m"
              memory: "2Gi"

      image: minio/minio:RELEASE.2024-01-01T16-36-33Z
      imagePullPolicy: IfNotPresent

      mountPath: /export

      requestAutoCert: false

      configuration:
        name: shared-storage-env-configuration

      s3:
        bucketDNS: false

      buckets:
        - name: packages
        - name: docs
  YAML

  depends_on = [helm_release.minio_operator]
}
