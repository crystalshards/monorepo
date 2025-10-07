class SaveJob < Job::SaveOperation
  permit_columns :title, :description, :company_name, :company_url, :location, :remote,
    :job_type, :salary_min, :salary_max, :salary_currency, :apply_url, :apply_email,
    :tags, :published_at, :expires_at, :featured, :active

  before_save do
    validate_required title, description, company_name, job_type
    validate_presence_of_at_least_one_of apply_url, apply_email
    validate_job_type
    validate_salary_range
  end

  private def validate_job_type
    return unless job_type.value

    valid_types = ["full-time", "part-time", "contract", "freelance", "internship"]
    unless valid_types.includes?(job_type.value)
      job_type.add_error("must be one of: #{valid_types.join(", ")}")
    end
  end

  private def validate_salary_range
    min = salary_min.value
    max = salary_max.value
    if min && max && min > max
      salary_max.add_error("must be greater than minimum salary")
    end
  end

  private def validate_presence_of_at_least_one_of(field1, field2)
    if field1.value.nil? && field2.value.nil?
      field1.add_error("must have either apply URL or apply email")
    end
  end
end
