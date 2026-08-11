# The only way anything becomes public.
#
# Approval is a deliberate human act, recorded with who did it and when. No
# ingestion path, no generator and no form can reach this: they all stop at a
# pending state and wait for an editor.
class ReviewContentItem < ContentItem::SaveOperation
  # No permitted columns at all. Everything this operation writes is decided
  # by the action from the signed-in editor, so there is nothing a request
  # body should be allowed to name.
  permit_columns

  attribute decision : String
  attribute reviewer : String
  # Attributes are nilable by default in Avram, so this is the optional one.
  attribute note : String

  DECISIONS = [ContentItem::State::APPROVED, ContentItem::State::REJECTED]

  before_save do
    validate_required decision, reviewer
    validate_inclusion_of decision, in: DECISIONS
    apply_decision
  end

  private def apply_decision
    return unless valid?

    state.value = decision.value.to_s
    reviewed_by.value = reviewer.value.to_s
    reviewed_at.value = Time.utc
    review_note.value = note.value.presence
  end
end
