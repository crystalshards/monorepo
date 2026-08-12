# Mail records for the domains that send.
#
# Resend issues these when a sending domain is added, and they are the whole of
# domain verification: without them Resend refuses to send and the CrystalBits
# newsletter has a working API key and no deliverability.
#
# They live in terraform rather than being clicked into Cloud DNS because this
# zone is terraform managed. A record added by hand survives right up until the
# next apply notices it is not in configuration.
#
# None of this is secret. A DKIM public key is published in DNS by design, which
# is the entire mechanism: a receiver fetches it from here to verify a signature
# it could not otherwise trust. It is the one piece of key material that belongs
# in version control.

locals {
  # Keyed by site slug so a second sending domain is one entry rather than a
  # second copy of this file. Only CrystalBits sends today. CrystalGigs will need
  # its own set when its Resend domain is created, and CrystalShards and
  # CrystalDocs send nothing and must not carry mail records at all.
  mail_domains = {
    crystalbits = {
      apex = "crystalbits.org"
      zone = google_dns_managed_zone.crystalbits_org.name

      # Verbatim from Resend. 218 characters, comfortably inside the 255 byte
      # limit for a single TXT string, so no chunking is needed. Verified to
      # decode as a 162 byte RSA SubjectPublicKeyInfo, which is how a truncated
      # or mangled paste would have been caught before it reached DNS rather
      # than as a verification that silently never completes.
      dkim_value = "p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQD+oK9bcT0Wtmj3RzW2xvQd0dVIJ8OWb4xemS6wZ0nwm1zJGnRoWZ+lg3eKY3JYhf0ZrOzhmlcyoM9MMH9PGdPGKRjUwrtObUP8n5wO7feo1MSRpoCqVYHTVyCvS3U1Kr3xNd47LbSQ9wk7k9ChDaIpoDOXUrjifZ29VP9E4fYeIwIDAQAB"

      spf_host     = "feedback-smtp.us-east-1.amazonses.com."
      inbound_host = "inbound-smtp.us-east-1.amazonaws.com."
    }
  }
}

# DKIM. The public half of the key Resend signs with.
resource "google_dns_record_set" "dkim" {
  for_each = local.mail_domains

  project      = var.project_id
  managed_zone = each.value.zone
  name         = "resend._domainkey.${each.value.apex}."
  type         = "TXT"
  ttl          = var.record_ttl

  # Quoted because Cloud DNS stores TXT as one or more character strings and
  # rejects an unquoted value containing spaces or a semicolon.
  rrdatas = ["\"${each.value.dkim_value}\""]
}

# SPF, on the `send` subdomain rather than the apex. Resend sends from
# send.<domain>, so the record authorising Amazon SES belongs there and the
# apex is left alone.
resource "google_dns_record_set" "spf_mx" {
  for_each = local.mail_domains

  project      = var.project_id
  managed_zone = each.value.zone
  name         = "send.${each.value.apex}."
  type         = "MX"
  ttl          = var.record_ttl
  rrdatas      = ["10 ${each.value.spf_host}"]
}

resource "google_dns_record_set" "spf_txt" {
  for_each = local.mail_domains

  project      = var.project_id
  managed_zone = each.value.zone
  name         = "send.${each.value.apex}."
  type         = "TXT"
  ttl          = var.record_ttl
  rrdatas      = ["\"v=spf1 include:amazonses.com ~all\""]
}

# DMARC at p=none, which is what Resend recommends to start: it asks receivers
# to report failures and to act on none of them. That is the right opening
# position for a domain that has never sent, because tightening to quarantine
# or reject before any real traffic has been observed rejects your own mail.
resource "google_dns_record_set" "dmarc" {
  for_each = local.mail_domains

  project      = var.project_id
  managed_zone = each.value.zone
  name         = "_dmarc.${each.value.apex}."
  type         = "TXT"
  ttl          = var.record_ttl
  rrdatas      = ["\"v=DMARC1; p=none;\""]
}

# Inbound mail, on the APEX.
#
# This is the one record here with an effect beyond verification: it makes SES
# the mail exchanger for the whole domain, so every message addressed to
# anything@<domain> goes to Amazon rather than wherever it went before. Safe
# here because these domains have been dark for years and nothing else receives
# on them, and worth stating plainly because it is not undone by deleting a
# record: mail delivered while this is wrong went somewhere else and does not
# come back.
resource "google_dns_record_set" "inbound_mx" {
  for_each = local.mail_domains

  project      = var.project_id
  managed_zone = each.value.zone
  name         = "${each.value.apex}."
  type         = "MX"
  ttl          = var.record_ttl
  rrdatas      = ["10 ${each.value.inbound_host}"]
}
