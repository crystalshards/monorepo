locals {
  # The five public sites. Every module that fans out per public app iterates
  # this, so adding a sixth site is one edit rather than a search for literals.
  #
  # trycrystal is here and deliberately NOT in database_apps below: phase 1 has
  # no database at all (DESIGN.md section 1, progress lives in the browser), so
  # it gets a Cloud Run service, a load balancer backend and DNS records, and
  # no Cloud SQL database, no schema migration Job, and no cloudsql.client
  # role. The two lists exist rather than one apps list with a flag because the
  # split is load bearing in both directions: a site accidentally added to
  # database_apps gets a provisioned database nobody asked for, and a database
  # app accidentally dropped from it stops migrating while still serving.
  public_apps = toset([
    "crystalshards",
    "crystaldocs",
    "crystalgigs",
    "crystalbits",
    "trycrystal",
  ])

  # The four applications backed by Cloud SQL. Everything that exists because a
  # database exists (module.database's databases and roles, the schema
  # migration Jobs and their identities) iterates this instead of public_apps.
  database_apps = toset([
    "crystalshards",
    "crystaldocs",
    "crystalgigs",
    "crystalbits",
  ])
}
