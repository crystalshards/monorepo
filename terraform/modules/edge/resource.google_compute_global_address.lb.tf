# The single anycast IPv4 address every one of the eight hostnames resolves to.
#
# This address is the reason the module exists. The A records these domains have
# carried for years point at 136.114.166.228, which belongs to nothing in this
# project, so the sites resolve to an address that answers for someone else.
# Reserving the address here means the value written into DNS is one terraform
# owns and will not lose.
resource "google_compute_global_address" "lb" {
  project      = var.project_id
  name         = "${var.name_prefix}-ip"
  description  = "Global anycast IP for the crystalshards, crystaldocs, crystalgigs and crystalbits load balancer"
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
}
