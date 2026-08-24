# Anti-spoofing records for a domain that sends no mail.
#
# A domain with no SPF and no DMARC can be spoofed freely: nothing tells a
# receiver that mail claiming to come from it is forged. The fix for a
# non-sending domain is the strictest possible pair, because there is no
# legitimate sender to accommodate. This is not the same job as the Resend
# records in resource.google_dns_record_set.mail.tf, which exist so a domain
# CAN send; these exist so this one cannot appear to.
#
# Why this file exists at all, which is the part worth remembering:
#
# trycrystal.org was already delegated to a zone in the waldrip-net project
# that carried "v=spf1 -all" and a DMARC reject policy. The zone this stack
# creates carried the A records and neither of those. So repointing the domain
# at this zone, which is what makes the site reachable, would have silently
# dropped the hardening and left an unprotected domain looking like a
# successful launch. The records land here first, and the delegation moves
# afterwards.
#
# crystalshards.org and crystaldocs.org are deliberately NOT in this map, even
# though crystaldocs.org serves "v=spf1 -all" today. That record was created by
# hand and is not in configuration, so adding it here would make terraform try
# to CREATE a record set that already exists and fail the apply with an
# already-exists error. Adopting the pre-existing records is a separate change
# with import blocks, of exactly the kind imports.edge.tf exists for. Only
# genuinely empty domains are managed here.
locals {
  # Site slug => apex and zone, for domains that must never send mail.
  non_sending_domains = {
    trycrystal = {
      apex = var.sites["trycrystal"].apex
      zone = google_dns_managed_zone.trycrystal_org.name
    }
  }
}

# "-all" rather than "~all": a hard fail, because there is no sender to be
# lenient towards. A softfail on a non-sending domain invites receivers to
# deliver forged mail to a spam folder instead of refusing it.
resource "google_dns_record_set" "no_send_spf" {
  for_each = local.non_sending_domains

  project      = var.project_id
  managed_zone = each.value.zone
  name         = "${each.value.apex}."
  type         = "TXT"
  ttl          = var.record_ttl

  # Quoted because Cloud DNS stores TXT as character strings and rejects an
  # unquoted value containing spaces.
  rrdatas = ["\"v=spf1 -all\""]
}

# p=reject, and sp=reject so subdomains are covered too. Strict alignment on
# both DKIM and SPF. Unlike a sending domain, where starting at p=none avoids
# rejecting your own mail before any traffic has been observed, a domain that
# sends nothing has no traffic to break: every message claiming to be from it
# is forged by definition.
#
# rua points at the same address the previous zone reported to, so aggregate
# reports keep arriving rather than silently stopping at the cutover.
resource "google_dns_record_set" "no_send_dmarc" {
  for_each = local.non_sending_domains

  project      = var.project_id
  managed_zone = each.value.zone
  name         = "_dmarc.${each.value.apex}."
  type         = "TXT"
  ttl          = var.record_ttl

  rrdatas = ["\"v=DMARC1; p=reject; sp=reject; adkim=s; aspf=s; rua=mailto:jason@waldrip.net; fo=1\""]
}
