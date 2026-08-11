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
end
