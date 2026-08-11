# The reader-facing submission form.
#
# The permit list is the security boundary. `state`, `origin`, `machine_drafted`
# and `source_url` are deliberately absent, so no combination of form fields can
# talk a submission into being public, into claiming to be a Crystal blog entry,
# or into colliding with an ingested item's deduplication key.
class SubmitContribution < ContentItem::SaveOperation
  permit_columns title, body, original_author, submitter_contact, canonical_url

  LICENSE_NOTE = "Submitted to CrystalBits by the author for publication here. " \
                 "Copyright remains with the author."

  before_save do
    # Defaults first. These columns are non-null, and Avram's own required
    # checks run against whatever the block leaves behind, so deferring them
    # until after validation would report "state is required" at a submitter
    # who was never offered the field.
    apply_editorial_defaults

    validate_required title, body, original_author, submitter_contact
    validate_size_of title, max: 200
    validate_size_of body, min: 40
    validate_contact
    validate_canonical_url
  end

  # Contact can be an email or a handle, because "@dana on the Crystal
  # Discord" is a perfectly good way to be reachable. Only something shaped
  # like an attempt at an email gets held to an email's rules, so a typo in an
  # address is caught while a handle is left alone.
  private def validate_contact
    return unless value = submitter_contact.value

    contact = value.strip
    submitter_contact.value = contact

    local, separator, domain = contact.partition('@')
    looks_like_email = !separator.empty? && !local.empty? && !contact.matches?(/\s/)
    return unless looks_like_email

    unless contact.matches?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/)
      submitter_contact.add_error("looks like an email address but is not a valid one. Use a full address, or a handle we can reach you on.")
    end
  end

  # A canonical link points at the author's own copy. It has to be a real
  # absolute web URL: a relative path would resolve against our domain and
  # credit us for their work.
  private def validate_canonical_url
    raw = canonical_url.value
    return if raw.nil? || raw.strip.empty?

    url = raw.strip
    canonical_url.value = url

    uri = URI.parse(url) rescue nil

    if uri.nil? || uri.host.nil? || !%w[http https].includes?(uri.scheme)
      canonical_url.add_error("must be a full http or https link, or left blank")
    end
  end

  # Everything the submitter does not get to choose.
  private def apply_editorial_defaults
    state.value = ContentItem::State::SUBMITTED
    origin.value = ContentItem::Origin::CONTRIBUTION
    machine_drafted.value = false
    license_note.value = LICENSE_NOTE

    # Left null on purpose. source_url is the deduplication key for ingested
    # items, and a contribution that claimed one could collide with a feed
    # entry or block a later ingestion.
    source_url.value = nil

    author = original_author.value.to_s.strip
    original_author.value = author
    # Derived rather than validated: a blank name fails on original_author,
    # and the submitter should not also be told that a field they never saw
    # is missing.
    attribution.value = author.empty? ? "Submitted anonymously" : "Submitted by #{author}"

    # Contributions carry the date they arrived so the public index can sort
    # every origin on one column.
    original_published_at.value ||= Time.utc

    if slug.value.to_s.strip.empty?
      slug.value = ContentSlug.generate(title.value.to_s)
    end

    if summary.value.to_s.strip.empty?
      summary.value = BitsHtml.plain_text(BitsHtml.markdown(body.value.to_s), 240).presence
    end
  end
end
