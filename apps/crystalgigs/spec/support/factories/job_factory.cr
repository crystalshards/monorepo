class JobFactory < Avram::Factory
  def initialize
    title "Senior Crystal Developer"
    description "We are looking for an experienced Crystal developer..."
    company_name "Crystal Corp"
    company_url "https://crystalcorp.example.com"
    location "San Francisco, CA"
    remote false
    job_type "full-time"
    salary_min 120000
    salary_max 180000
    salary_currency "USD"
    apply_url "https://crystalcorp.example.com/careers/senior-developer"
    tags ["crystal", "backend", "web"]
    published_at Time.utc
    expires_at Time.utc + 30.days
    active true
  end
end
