# One row per piece of editorial content, whatever produced it.
#
# Three sources feed this table: contributions from readers, entries ingested
# from the Crystal blog feed, and summaries we draft ourselves from community
# discussion. They share a table because they share a review: the only thing
# that puts anything in front of the public is a human moving it to APPROVED.
class ContentItem < BaseModel
  # Where the item came from.
  module Origin
    CONTRIBUTION = "contribution"
    CRYSTAL_BLOG = "crystal_blog"
    GENERATED    = "generated"

    ALL = [CONTRIBUTION, CRYSTAL_BLOG, GENERATED]
  end

  # A reader's submission arrives as SUBMITTED and everything we pull in or
  # write ourselves arrives as DRAFT. The distinction is only there so a
  # reviewer can tell at a glance whether a person is waiting on an answer.
  # Neither is public. APPROVED is the single state that is.
  module State
    SUBMITTED = "submitted"
    DRAFT     = "draft"
    APPROVED  = "approved"
    REJECTED  = "rejected"

    ALL     = [SUBMITTED, DRAFT, APPROVED, REJECTED]
    PENDING = [SUBMITTED, DRAFT]
  end

  table do
    column origin : String
    column state : String

    column title : String
    column slug : String
    column body : String?
    column summary : String?

    column source_url : String?
    column original_author : String?
    column original_published_at : Time?
    column attribution : String
    column license_note : String?

    column machine_drafted : Bool = false
    column source_urls : Array(String) = [] of String

    column submitter_contact : String?
    column canonical_url : String?

    column reviewed_at : Time?
    column reviewed_by : String?
    column review_note : String?
  end

  # The single definition of "the public may see this". Pages and queries both
  # go through it so there is one place to be wrong, and one place to fix.
  def publicly_visible? : Bool
    state == State::APPROVED
  end

  def pending_review? : Bool
    State::PENDING.includes?(state)
  end

  def rejected? : Bool
    state == State::REJECTED
  end

  def contribution? : Bool
    origin == Origin::CONTRIBUTION
  end

  def from_crystal_blog? : Bool
    origin == Origin::CRYSTAL_BLOG
  end

  def generated? : Bool
    origin == Origin::GENERATED
  end

  # Feed entries are a headline, a summary and a link. We deliberately do not
  # hold their bodies, so there is nothing of theirs to read on our site and
  # the only way to read the article is to go to the Crystal blog.
  def links_out_only? : Bool
    body.nil? && !source_url.nil?
  end

  def read_url : String
    if links_out_only?
      source_url.to_s
    else
      "/news/#{slug}"
    end
  end

  def origin_label : String
    case origin
    when Origin::CONTRIBUTION then "Community contribution"
    when Origin::CRYSTAL_BLOG then "Crystal blog"
    when Origin::GENERATED    then "Machine-drafted by CrystalBits"
    else                           origin
    end
  end
end
