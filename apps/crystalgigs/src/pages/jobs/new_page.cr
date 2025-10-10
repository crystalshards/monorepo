class Jobs::NewPage < MainLayout
  needs operation : SaveJob

  def page_title
    "Post a Job"
  end

  def content
    div class: "page-header" do
      h1 do
        text "Post a Job"
      end
      para do
        text "Reach thousands of Crystal developers"
      end
    end

    section class: "form-section" do
      div class: "form-container" do
        render_pricing_info

        form_for Jobs::Create, class: "job-form" do
          render_basic_info
          render_job_details
          render_compensation
          render_application_info
          render_form_actions
        end
      end
    end
  end

  private def render_pricing_info
    div class: "pricing-info" do
      h3 do
        text "Job Posting - $99 for 60 days"
      end
      ul do
        li do
          text "Reach thousands of Crystal developers"
        end
        li do
          text "60 days of visibility"
        end
        li do
          text "Featured in weekly newsletter"
        end
        li do
          text "Shared on social media"
        end
        li do
          text "Edit anytime during posting period"
        end
      end
    end
  end

  private def render_basic_info
    fieldset do
      legend do
        text "Basic Information"
      end

      div class: "form-group" do
        label for: "job_title" do
          text "Job Title"
        end
        input(
          type: "text",
          name: "job:title",
          id: "job_title",
          value: @operation.title.value.to_s,
          placeholder: "e.g., Senior Crystal Developer",
          required: true
        )
        render_errors(@operation.title)
        para class: "field-help" do
          text "Be specific and descriptive"
        end
      end

      div class: "form-group" do
        label for: "job_company_name" do
          text "Company Name"
        end
        input(
          type: "text",
          name: "job:company_name",
          id: "job_company_name",
          value: @operation.company_name.value.to_s,
          placeholder: "Your Company Inc.",
          required: true
        )
        render_errors(@operation.company_name)
      end

      div class: "form-group" do
        label for: "job_company_url" do
          text "Company Website"
        end
        input(
          type: "url",
          name: "job:company_url",
          id: "job_company_url",
          value: @operation.company_url.value.to_s,
          placeholder: "https://yourcompany.com"
        )
        render_errors(@operation.company_url)
      end
    end
  end

  private def render_job_details
    fieldset do
      legend do
        text "Job Details"
      end

      div class: "form-group" do
        label for: "job_description" do
          text "Job Description"
        end
        textarea(
          name: "job:description",
          id: "job_description",
          placeholder: "Describe the role, responsibilities, and requirements...",
          required: true
        ) do
          text @operation.description.value.to_s
        end
        render_errors(@operation.description)
        para class: "field-help" do
          text "Supports Markdown formatting. Include responsibilities, requirements, and benefits."
        end
      end

      div class: "form-row" do
        div class: "form-group" do
          label for: "job_location" do
            text "Location"
          end
          input(
            type: "text",
            name: "job:location",
            id: "job_location",
            value: @operation.location.value.to_s,
            placeholder: "San Francisco, CA"
          )
          render_errors(@operation.location)
        end

        div class: "form-group" do
          label for: "job_job_type" do
            text "Job Type"
          end
          tag "select", name: "job:job_type", id: "job_job_type", required: "required" do
            option value: "", selected: @operation.job_type.value.nil? do
              text "Select job type"
            end
            option value: "full-time", selected: @operation.job_type.value == "full-time" do
              text "Full Time"
            end
            option value: "part-time", selected: @operation.job_type.value == "part-time" do
              text "Part Time"
            end
            option value: "contract", selected: @operation.job_type.value == "contract" do
              text "Contract"
            end
            option value: "freelance", selected: @operation.job_type.value == "freelance" do
              text "Freelance"
            end
            option value: "internship", selected: @operation.job_type.value == "internship" do
              text "Internship"
            end
          end
          render_errors(@operation.job_type)
        end
      end

      div class: "form-checkbox" do
        input(
          type: "checkbox",
          name: "job:remote",
          id: "job_remote",
          value: "true",
          checked: @operation.remote.value == true
        )
        label for: "job_remote" do
          text "This is a remote position"
        end
      end

      div class: "form-group" do
        label for: "job_tags_string" do
          text "Skills & Technologies"
        end
        input(
          type: "text",
          name: "job:tags_string",
          id: "job_tags_string",
          value: @operation.tags_string.value.to_s,
          placeholder: "Crystal, PostgreSQL, Docker, AWS"
        )
        para class: "field-help" do
          text "Comma-separated list of skills and technologies"
        end
      end
    end
  end

  private def render_compensation
    fieldset do
      legend do
        text "Compensation"
      end

      para class: "field-help" do
        text "Salary information is optional but recommended"
      end

      div class: "form-row" do
        div class: "form-group" do
          label for: "job_salary_min" do
            text "Minimum Salary"
          end
          input(
            type: "number",
            name: "job:salary_min",
            id: "job_salary_min",
            value: @operation.salary_min.value.to_s,
            placeholder: "80000",
            min: "0",
            step: "1000"
          )
          render_errors(@operation.salary_min)
        end

        div class: "form-group" do
          label for: "job_salary_max" do
            text "Maximum Salary"
          end
          input(
            type: "number",
            name: "job:salary_max",
            id: "job_salary_max",
            value: @operation.salary_max.value.to_s,
            placeholder: "120000",
            min: "0",
            step: "1000"
          )
          render_errors(@operation.salary_max)
        end

        div class: "form-group" do
          label for: "job_salary_currency" do
            text "Currency"
          end
          tag "select", name: "job:salary_currency", id: "job_salary_currency" do
            option value: "USD", selected: @operation.salary_currency.value == "USD" do
              text "USD"
            end
            option value: "EUR", selected: @operation.salary_currency.value == "EUR" do
              text "EUR"
            end
            option value: "GBP", selected: @operation.salary_currency.value == "GBP" do
              text "GBP"
            end
            option value: "CAD", selected: @operation.salary_currency.value == "CAD" do
              text "CAD"
            end
            option value: "AUD", selected: @operation.salary_currency.value == "AUD" do
              text "AUD"
            end
          end
        end
      end
    end
  end

  private def render_application_info
    fieldset do
      legend do
        text "How to Apply"
      end

      para class: "field-help-important" do
        text "Provide at least one: Application URL or Email"
      end

      div class: "form-group" do
        label for: "job_apply_url" do
          text "Application URL"
        end
        input(
          type: "url",
          name: "job:apply_url",
          id: "job_apply_url",
          value: @operation.apply_url.value.to_s,
          placeholder: "https://yourcompany.com/careers/apply"
        )
        render_errors(@operation.apply_url)
        para class: "field-help" do
          text "Link to your application page or ATS"
        end
      end

      div class: "form-group" do
        label for: "job_apply_email" do
          text "Application Email"
        end
        input(
          type: "email",
          name: "job:apply_email",
          id: "job_apply_email",
          value: @operation.apply_email.value.to_s,
          placeholder: "jobs@yourcompany.com"
        )
        render_errors(@operation.apply_email)
        para class: "field-help" do
          text "Email where candidates can send applications"
        end
      end
    end
  end

  private def render_form_actions
    div class: "form-actions" do
      button type: "submit", class: "button button-primary button-large" do
        text "Continue to Payment - $99"
      end
    end
  end

  private def render_errors(field)
    return unless field.errors.any?

    div class: "field-errors" do
      field.errors.each do |error|
        para class: "field-error" do
          text error
        end
      end
    end
  end
end
