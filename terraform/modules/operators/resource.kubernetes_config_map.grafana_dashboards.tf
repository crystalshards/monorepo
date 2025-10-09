# ConfigMap for Lucky Apps dashboard
resource "kubernetes_config_map" "grafana_dashboard_lucky_apps" {
  metadata {
    name      = "grafana-dashboard-lucky-apps"
    namespace = "monitoring"
    labels = {
      grafana_dashboard = "1"
      grafana_folder    = "CrystalShards"
    }
  }

  data = {
    "lucky-apps-overview.json" = file("${path.module}/dashboards/lucky-apps-overview.json")
  }

  depends_on = [helm_release.prometheus_operator]
}

# ConfigMap for PostgreSQL dashboard
resource "kubernetes_config_map" "grafana_dashboard_postgresql" {
  metadata {
    name      = "grafana-dashboard-postgresql"
    namespace = "monitoring"
    labels = {
      grafana_dashboard = "1"
      grafana_folder    = "Infrastructure"
    }
  }

  data = {
    "postgresql-overview.json" = file("${path.module}/dashboards/postgresql-overview.json")
  }

  depends_on = [helm_release.prometheus_operator]
}

# ConfigMap for Redis dashboard
resource "kubernetes_config_map" "grafana_dashboard_redis" {
  metadata {
    name      = "grafana-dashboard-redis"
    namespace = "monitoring"
    labels = {
      grafana_dashboard = "1"
      grafana_folder    = "Infrastructure"
    }
  }

  data = {
    "redis-overview.json" = file("${path.module}/dashboards/redis-overview.json")
  }

  depends_on = [helm_release.prometheus_operator]
}

# ConfigMap for MinIO dashboard
resource "kubernetes_config_map" "grafana_dashboard_minio" {
  metadata {
    name      = "grafana-dashboard-minio"
    namespace = "monitoring"
    labels = {
      grafana_dashboard = "1"
      grafana_folder    = "Infrastructure"
    }
  }

  data = {
    "minio-overview.json" = file("${path.module}/dashboards/minio-overview.json")
  }

  depends_on = [helm_release.prometheus_operator]
}

# ConfigMap for GKE Cluster dashboard
resource "kubernetes_config_map" "grafana_dashboard_gke" {
  metadata {
    name      = "grafana-dashboard-gke"
    namespace = "monitoring"
    labels = {
      grafana_dashboard = "1"
      grafana_folder    = "Infrastructure"
    }
  }

  data = {
    "gke-cluster-overview.json" = file("${path.module}/dashboards/gke-cluster-overview.json")
  }

  depends_on = [helm_release.prometheus_operator]
}
