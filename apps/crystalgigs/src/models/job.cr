class Job < BaseModel
  # A posting created on CrystalGigs itself rather than imported from an ATS.
  SOURCE_DIRECT = "direct"

  table do
    column title : String
    column description : String
    column company_name : String
    column company_url : String?
    column location : String?
    column remote : Bool = false
    column job_type : String
    column salary_min : Int32?
    column salary_max : Int32?
    column salary_currency : String = "USD"
    column apply_url : String?
    column apply_email : String?
    column tags : Array(String) = [] of String
    column published_at : Time?
    column expires_at : Time?
    column featured : Bool = false
    column active : Bool = true

    # Provenance. `source` is "direct" or an ATS provider key, `external_id`
    # is the provider-side id. Together they are the import dedupe key.
    column source : String = SOURCE_DIRECT
    column external_id : String?
    column delisted_at : Time?

    belongs_to ats_connection : AtsConnection?
    has_many job_applications : JobApplication
  end

  def imported? : Bool
    source != SOURCE_DIRECT
  end

  # The posting vanished from the employer's board upstream.
  def delisted? : Bool
    !delisted_at.nil?
  end

  # Whether this posting has ever gone live, as opposed to a draft still
  # waiting on payment. A direct posting only gets a `published_at` once its
  # $99 clears (`Jobs::Checkout#publish`); an imported posting gets one the
  # moment the ATS sync creates it, no payment involved. Either way this one
  # column is already the board's own answer to "is this real yet", so
  # nothing downstream - the show page, Google's structured data - needs a
  # second concept of "published" layered on top.
  def published? : Bool
    !published_at.nil?
  end

  # Whether the posting's own paid window has run out. Mirrors
  # `JobQuery#not_expired` at the row level: no expiry date means the
  # posting was never given one, which is "not expired", not "unknown".
  def expired? : Bool
    if window_end = expires_at
      window_end <= Time.utc
    else
      false
    end
  end

  # Whether this posting should read as an open role anywhere it is
  # advertised: the board's own jobs list, the ad feed, and Google Jobs
  # alike. The same three signals `JobQuery#active_only.published_only
  # .not_expired` already filters the board's listings by, combined here at
  # the row level so a single job can answer the same question about
  # itself. A posting that is published but no longer open (expired or
  # delisted) is a different case from one that was never published at all
  # - see `Jobs::Show`, which tells them apart because only the former
  # deserves a "gone" response.
  def open? : Bool
    published? && active && !expired?
  end

  # The description exactly as the job's own page shows it: escaped first so
  # a posting cannot inject markup, then given back its line breaks. Shared
  # with the JobPosting structured data so the two can never read
  # differently - Google's own content policy calls out "content on pages
  # found to be different than structured data on the page" as a
  # violation, and the surest way to never drift is to have one method
  # instead of two copies of the same transformation.
  #
  # A job description is written by whoever posts the job, so this is
  # untrusted input. Escape first, then add the line breaks: the reverse
  # order would escape the breaks just inserted, and escaping afterwards
  # would be no protection at all. This is the only markup this method has
  # ever produced: it is a newline-to-break conversion, not a Markdown
  # renderer.
  def description_html : String
    HTML.escape(description).gsub("\n", "<br>")
  end
end
