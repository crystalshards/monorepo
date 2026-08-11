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
# pool, so the ceiling is the product of instances and pool size, not the sum:
#   crystalshards  5 instances x 2 pools (own + crystaldocs) x 5 =  50
#   crystaldocs    5 instances x 2 pools (own + crystalshards) x 5 = 50
#   crystalgigs    5 instances x 1 pool x 5                       =  25
#   crystalbits    5 instances x 1 pool x 5                       =  25
#   4 migration Jobs, 1 task each, 1 pool x 5                     =  20
#                                                            total  170
# against max_connections 200. Raise max_instances in the services module and
# this arithmetic is what you have to redo.
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
