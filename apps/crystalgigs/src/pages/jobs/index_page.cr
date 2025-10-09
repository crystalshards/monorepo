class Jobs::IndexPage < MainLayout
  needs jobs : Array(Job)
  needs query : String?
  needs location : String?
  needs remote : String?
  needs job_type : String?
  needs page : Int32
  needs total_pages : Int32

  def page_title
    "Browse Jobs"
  end

  def content
    section class: "page-header" do
      h1 do
        text "Browse Crystal Jobs"
      end
      para do
        text "Find your perfect role in the Crystal ecosystem"
      end
    end

    section class: "filters-section" do
      mount SearchBar, query: @query, large: false

      form_tag action: "/jobs", method: "get", class: "filters-form" do
        div class: "filter-group" do
          label "Location", for: "location"
          input type: "text",
            name: "location",
            id: "location",
            value: @location,
            placeholder: "e.g. San Francisco, Remote"
        end

        div class: "filter-group" do
          label "Job Type", for: "job_type"
          select_tag name: "job_type", id: "job_type" do
            option value: "", selected: @job_type.nil? do
              text "All Types"
            end
            option value: "full-time", selected: @job_type == "full-time" do
              text "Full Time"
            end
            option value: "part-time", selected: @job_type == "part-time" do
              text "Part Time"
            end
            option value: "contract", selected: @job_type == "contract" do
              text "Contract"
            end
            option value: "freelance", selected: @job_type == "freelance" do
              text "Freelance"
            end
            option value: "internship", selected: @job_type == "internship" do
              text "Internship"
            end
          end
        end

        div class: "filter-group filter-checkbox" do
          input type: "checkbox",
            name: "remote",
            id: "remote",
            value: "true",
            checked: @remote == "true"
          label "Remote Only", for: "remote"
        end

        hidden_field name: "query", value: @query if @query

        button type: "submit", class: "button button-secondary" do
          text "Apply Filters"
        end
      end
    end

    section class: "jobs-list-section" do
      if @jobs.any?
        div class: "jobs-count" do
          text "Showing jobs"
        end

        div class: "job-list" do
          @jobs.each do |job|
            mount JobCard, job: job
          end
        end

        if @total_pages > 1
          mount Pagination, current_page: @page, total_pages: @total_pages
        end
      else
        div class: "empty-state" do
          h3 do
            text "No jobs found"
          end
          para do
            text "Try adjusting your search criteria or "
            a href: "/jobs" do
              text "view all jobs"
            end
          end
        end
      end
    end
  end
end
