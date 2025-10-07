class Job < BaseModel
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
    column apply_url : String
    column apply_email : String?
    column tags : Array(String) = [] of String
    column published_at : Time?
    column expires_at : Time?
    column featured : Bool = false
    column active : Bool = true
  end
end
