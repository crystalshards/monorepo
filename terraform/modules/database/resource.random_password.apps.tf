# One login role password per application.
#
# No punctuation. The password is interpolated into a postgres:// URL, and a
# generated "@", "/", "?" or "#" changes where the parser thinks the userinfo
# ends. Forty characters of mixed case alphanumerics is around 238 bits, so
# dropping the symbol classes costs nothing worth having and removes an entire
# category of failure that would only surface at connection time.
resource "random_password" "apps" {
  for_each = var.apps

  length  = 40
  special = false
}
