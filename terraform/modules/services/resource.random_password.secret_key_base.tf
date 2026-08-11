# Lucky signs sessions and cookies with SECRET_KEY_BASE and refuses to boot in
# production without one. Generated here, never typed, never defaulted, and the
# only copy lives in Secret Manager.
#
# docs-launcher gets its own rather than borrowing the registry's. It is built
# from the same codebase and so demands the variable at boot, but sharing the
# value would let the build dispatcher forge crystalshards session cookies for
# no reason beyond saving one resource.
resource "random_password" "secret_key_base" {
  for_each = local.lucky_services

  length  = 64
  special = false
}
