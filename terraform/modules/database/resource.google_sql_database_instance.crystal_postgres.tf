# The single Postgres instance behind all four applications.
#
# Connectivity: public IP is ENABLED and private IP is not configured. That
# reads backwards until you follow the socket. Cloud Run reaches Cloud SQL
# through the connector built into the runtime, mounted as a unix socket at
# /cloudsql/<connection_name>. That connector authenticates with ephemeral
# certificates from the Cloud SQL Admin API and rides Google's internal
# network, and it requires the instance to have a public IP. Turning the public
# IP off does not harden this path, it deletes it, and the replacement is a
# Serverless VPC Access connector or Direct VPC egress against a private IP,
# which means keeping a VPC, a subnet and a private services access range alive
# purely to host a route the socket already provides. The VPC is being deleted.
#
# What actually closes the public IP is below it: authorized_networks is empty,
# so no address anywhere is permitted to open a TCP connection, and require_ssl
# rejects anything unencrypted that somehow tried. The only identities that can
# reach this instance at all are the service accounts holding
# roles/cloudsql.client, which are the four application services, the four
# migration Jobs, and nothing else. docs-build in particular holds no such role.
#
# Connection budget. Cloud Run gives every instance of every service its own
# pool, so the ceiling is the product of instances and pool size, not the sum.
# On 2026-09-25, Jason decided to move crystal-postgres to shared core
# db-g1-small (1 shared vCPU, 1.7 GB RAM). With connection_pool_size set to 2:
#   crystalshards       3 instances x 2 pools (own + crystaldocs) x 2 = 12
#   crystaldocs         3 instances x 2 pools (own + crystalshards) x 2 = 12
#   crystalgigs         2 instances x 1 pool x 2                       =  4
#   crystalbits         2 instances x 1 pool x 2                       =  4
#   docs-launcher       5 instances x 2 pools (crystalshards + docs) x 2 = 20
#   4 migration Jobs    1 task each x 1 pool x 2                       =  8
#   discover-shards     1 task x 1 pool x 2                            =  2
#   warm-popular-docs   1 task x 2 pools x 2                           =  4
#   docs-status-reconcile 1 task x 2 pools x 2                         =  4
#   Cloud SQL reserved superuser connections (PostgreSQL default)       =  3
#                                                                total   73
# against max_connections 80 (7 headroom).
#
# Measured production usage over 30 days (2026-08-26 to 2026-09-25) justifies
# these numbers:
#   postgresql/num_backends: min 0, p50 2, p99 8, peak 16
#   memory/usage: min 1.14 GB, p50 1.33 GB, p99 1.42 GB, peak 1.47 GB
#   memory/total_usage: min 310 MB, p50 500 MB, p99 599 MB, peak 615 MB
#   cpu/utilization: min 6.7%, p50 9.2%, p99 13.4%, peak 39.5%
#   active instances: crystalshards p99 1 (max 3), crystaldocs p99 2 (max 5),
#   crystalgigs p99 1 (max 2), crystalbits p99 1 (max 2)
# Under normal operation the entire fleet uses only 2 to 8 connections, so 80
# provides 5x headroom over measured peak while capping the absolute worst case
# safely below the 1.7 GB memory limit of db-g1-small.
resource "google_sql_database_instance" "crystal_postgres" {
  project          = var.project_id
  name             = "crystal-postgres"
  region           = var.region
  database_version = "POSTGRES_16"

  # Refuses `terraform destroy` on the one resource in this stack that holds
  # state nothing else can regenerate.
  deletion_protection = true

  settings {
    tier              = var.tier
    edition           = "ENTERPRISE"
    availability_type = "ZONAL"
    disk_type         = "PD_SSD"
    disk_size         = 10
    disk_autoresize   = true

    # The API side twin of deletion_protection above. The terraform flag stops
    # a plan, this one stops a console click or a stray gcloud.
    deletion_protection_enabled = true

    ip_configuration {
      ipv4_enabled = true
      require_ssl  = true
      # Deliberately empty. Every consumer arrives over the Cloud SQL socket,
      # so there is no address that should be allowed to dial the public IP.
      # Adding an entry here is how this instance becomes internet reachable.
    }

    backup_configuration {
      enabled                        = true
      start_time                     = "08:00"
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7

      backup_retention_settings {
        retained_backups = var.backup_retained_count
        retention_unit   = "COUNT"
      }
    }

    database_flags {
      name  = "max_connections"
      value = tostring(var.max_connections)
    }

    insights_config {
      query_insights_enabled  = true
      record_application_tags = true
    }

    maintenance_window {
      day          = 7
      hour         = 9
      update_track = "stable"
    }

    user_labels = {
      environment = "production"
      managed_by  = "terraform"
    }
  }
}
