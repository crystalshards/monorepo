class ContentItemFactory < Avram::Factory
  def initialize
    unique = "#{Time.utc.to_unix_ms}-#{Random.rand(1_000_000)}"

    origin ContentItem::Origin::CONTRIBUTION
    # Draft by default. A factory that produced public rows would let a spec
    # pass while the thing it is guarding is broken.
    state ContentItem::State::DRAFT
    title "Fibers and execution contexts #{unique}"
    slug "fibers-and-execution-contexts-#{unique}"
    body "Some **markdown** about Crystal."
    summary "Some markdown about Crystal."
    source_url nil
    original_author "A Contributor"
    original_published_at Time.utc
    attribution "Submitted by A Contributor"
    license_note nil
    machine_drafted false
    source_urls [] of String
    submitter_contact nil
    canonical_url nil
  end

  def approved
    state ContentItem::State::APPROVED
    reviewed_at Time.utc
    reviewed_by "editor"
    self
  end
end
