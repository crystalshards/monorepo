class Jobs::IndexPage < MainLayout
  needs jobs : Array(Job)
  needs query : String?
  needs location : String?
  needs job_type : String?
  needs remote : Bool?
  needs current_page : Int32
  needs total_pages : Int32
  needs total_count : Int64

  def page_title
    "Browse Crystal Jobs"
  end

  def content
    div class: "page-header" do
      h1 do
        text "Browse Crystal Jobs"
      end
      para do
        text "Find your next opportunity working with Crystal"
      end
    end

    mount SearchBar, query: @query

    render_filters

    section class: "jobs-list-section" do
      para class: "jobs-count" do
        text "#{@total_count} job#{"s" unless @total_count == 1} found"
      end

      if @jobs.any?
        div class: "job-list" do
          @jobs.each do |job|
            mount JobCard, job: job, featured: job.featured
          end
        end

        render_pagination
      else
        render_empty_state
      end
    end
  end

  private def render_filters
    section class: "filters-section" do
      h3 do
        text "Filter Jobs"
      end

      form action: "/jobs", method: "get", class: "filters-form" do
        if q = @query
          input type: "hidden", name: "query", value: q
        end

        div class: "filter-group" do
          label do
            text "Location"
          end
          input(
            type: "text",
            name: "location",
            value: @location || "",
            placeholder: "e.g., San Francisco, Remote"
          )
        end

        div class: "filter-group" do
          label do
            text "Job Type"
          end
          tag "select", name: "job_type" do
            select_option("All Types", "", @job_type.nil?)
            select_option("Full Time", "full-time", @job_type == "full-time")
            select_option("Part Time", "part-time", @job_type == "part-time")
            select_option("Contract", "contract", @job_type == "contract")
            select_option("Freelance", "freelance", @job_type == "freelance")
            select_option("Internship", "internship", @job_type == "internship")
          end
        end

        div class: "filter-checkbox" do
          checkbox_input("remote", "remote-checkbox", "true", @remote == true)
          label for: "remote-checkbox" do
            text "Remote only"
          end
        end

        div class: "filter-group" do
          button type: "submit", class: "button button-primary" do
            text "Apply Filters"
          end
        end
      end
    end
  end

  private def render_pagination
    return if @total_pages <= 1

    div class: "pagination" do
      if @current_page > 1
        a href: build_page_url(@current_page - 1), class: "pagination-link" do
          text "← Previous"
        end
      end

      span class: "pagination-info" do
        text "Page #{@current_page} of #{@total_pages}"
      end

      if @current_page < @total_pages
        a href: build_page_url(@current_page + 1), class: "pagination-link" do
          text "Next →"
        end
      end
    end
  end

  private def build_page_url(page : Int32) : String
    params = [] of String
    params << "page=#{page}"
    params << "query=#{URI.encode_www_form(@query.to_s)}" if @query
    params << "location=#{URI.encode_www_form(@location.to_s)}" if @location
    params << "job_type=#{@job_type}" if @job_type
    params << "remote=true" if @remote

    "/jobs?#{params.join("&")}"
  end

  private def render_empty_state
    div class: "empty-state" do
      h3 do
        text "No jobs found"
      end
      para do
        if @query || @location || @job_type || @remote
          text "Try adjusting your filters to see more results"
        else
          text "There are no active job postings at the moment. Check back soon!"
        end
      end
      a href: "/jobs", class: "button button-secondary" do
        text "Clear Filters"
      end
    end
  end
end
