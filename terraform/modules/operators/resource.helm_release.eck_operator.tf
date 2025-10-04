# Elastic Cloud on Kubernetes (ECK) Operator
resource "helm_release" "eck_operator" {
  name       = "elastic-operator"
  repository = "https://helm.elastic.co"
  chart      = "eck-operator"
  version    = "~> 2.14"
  namespace  = "elastic-system"

  create_namespace = true

  values = [yamlencode({
    resources = {
      limits = {
        cpu    = "200m"
        memory = "256Mi"
      }
      requests = {
        cpu    = "50m"
        memory = "128Mi"
      }
    }

    # Enable webhook for validation
    webhook = {
      enabled = true
    }

    # Configure for GKE Autopilot
    podSecurityContext = {
      runAsNonRoot = true
      runAsUser    = 1000
    }
  })]
}

# Elasticsearch cluster for APM data storage
resource "kubectl_manifest" "elasticsearch" {
  yaml_body = <<-YAML
    apiVersion: elasticsearch.k8s.elastic.co/v1
    kind: Elasticsearch
    metadata:
      name: elasticsearch
      namespace: elastic-system
    spec:
      version: 8.16.0
      nodeSets:
      - name: default
        count: 1
        config:
          node.store.allow_mmap: false
        podTemplate:
          spec:
            containers:
            - name: elasticsearch
              resources:
                requests:
                  cpu: 500m
                  memory: 2Gi
                limits:
                  cpu: 2000m
                  memory: 4Gi
        volumeClaimTemplates:
        - metadata:
            name: elasticsearch-data
          spec:
            accessModes:
            - ReadWriteOnce
            resources:
              requests:
                storage: 10Gi
  YAML

  depends_on = [helm_release.eck_operator]
}

# Kibana for visualization
resource "kubectl_manifest" "kibana" {
  yaml_body = <<-YAML
    apiVersion: kibana.k8s.elastic.co/v1
    kind: Kibana
    metadata:
      name: kibana
      namespace: elastic-system
    spec:
      version: 8.16.0
      count: 1
      elasticsearchRef:
        name: elasticsearch
      podTemplate:
        spec:
          containers:
          - name: kibana
            resources:
              requests:
                cpu: 200m
                memory: 512Mi
              limits:
                cpu: 1000m
                memory: 1Gi
  YAML

  depends_on = [kubectl_manifest.elasticsearch]
}

# APM Server to receive traces from OpenTelemetry
resource "kubectl_manifest" "apm_server" {
  yaml_body = <<-YAML
    apiVersion: apm.k8s.elastic.co/v1
    kind: ApmServer
    metadata:
      name: elastic-apm
      namespace: elastic-system
    spec:
      version: 8.16.0
      count: 1
      elasticsearchRef:
        name: elasticsearch
      podTemplate:
        spec:
          containers:
          - name: apm-server
            resources:
              requests:
                cpu: 200m
                memory: 512Mi
              limits:
                cpu: 1000m
                memory: 1Gi
  YAML

  depends_on = [kubectl_manifest.elasticsearch]
}
