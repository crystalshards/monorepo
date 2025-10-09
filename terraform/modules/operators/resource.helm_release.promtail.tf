# Promtail DaemonSet for shipping logs to Loki
resource "helm_release" "promtail" {
  name       = "promtail"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "promtail"
  version    = "~> 6.0"
  namespace  = "monitoring"

  timeout = 600   # 10 minutes
  wait    = false # Disable wait - Promtail may take time to stabilize in Autopilot

  values = [
    yamlencode({
      config = {
        # Send logs to Loki
        clients = [{
          url = "http://loki-gateway:80/loki/api/v1/push"
        }]

        # Scrape configs for different log sources
        snippets = {
          # Scrape all pod logs
          scrapeConfigs = <<-EOT
          # Pods with label 'app'
          - job_name: kubernetes-pods
            kubernetes_sd_configs:
              - role: pod
            relabel_configs:
              # Add namespace label
              - source_labels: [__meta_kubernetes_namespace]
                action: replace
                target_label: namespace
              # Add pod name label
              - source_labels: [__meta_kubernetes_pod_name]
                action: replace
                target_label: pod
              # Add container name label
              - source_labels: [__meta_kubernetes_pod_container_name]
                action: replace
                target_label: container
              # Add app label if it exists
              - source_labels: [__meta_kubernetes_pod_label_app]
                action: replace
                target_label: app
              # Add job label from annotation
              - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_job]
                action: replace
                target_label: job
              # Drop logs from kube-system (too noisy)
              - source_labels: [__meta_kubernetes_namespace]
                regex: kube-system
                action: drop

          # System component logs
          - job_name: kubernetes-system
            kubernetes_sd_configs:
              - role: pod
            relabel_configs:
              - source_labels: [__meta_kubernetes_namespace]
                regex: (envoy-gateway-system|monitoring|cert-manager|infrastructure)
                action: keep
              - source_labels: [__meta_kubernetes_namespace]
                action: replace
                target_label: namespace
              - source_labels: [__meta_kubernetes_pod_name]
                action: replace
                target_label: pod
              - source_labels: [__meta_kubernetes_pod_container_name]
                action: replace
                target_label: container
          EOT
        }
      }

      # DaemonSet resources (runs on every node)
      resources = {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "200m"
          memory = "256Mi"
        }
      }

      # Tolerate all taints to ensure it runs on all nodes
      tolerations = [
        {
          effect   = "NoSchedule"
          operator = "Exists"
        }
      ]

      # Service monitor for Prometheus metrics
      serviceMonitor = {
        enabled = true
        labels = {
          release = "prometheus-operator"
        }
      }

      # Priority class for critical log collection
      priorityClassName = "system-node-critical"

      # GKE Autopilot compatibility: Override default volumes
      # Default chart tries to mount /var/lib/docker/containers which is prohibited in Autopilot
      # Only /var/log/* paths are allowed for hostPath volumes, and ONLY in read-only mode
      # Reference: https://cloud.google.com/kubernetes-engine/docs/concepts/autopilot-security#file-system
      defaultVolumes = [
        # Use emptyDir for position tracking instead of hostPath (write access needed)
        {
          name     = "run"
          emptyDir = {}
        },
        # Keep /var/log/pods (allowed in Autopilot, read-only)
        {
          name = "pods"
          hostPath = {
            path = "/var/log/pods"
          }
        }
        # Remove /var/lib/docker/containers - not allowed in Autopilot
      ]

      defaultVolumeMounts = [
        {
          name      = "run"
          mountPath = "/run/promtail"
          # Write access allowed with emptyDir
        },
        {
          name      = "pods"
          mountPath = "/var/log/pods"
          readOnly  = true
        }
        # Remove /var/lib/docker/containers mount
      ]
    })
  ]

  depends_on = [helm_release.loki]
}
